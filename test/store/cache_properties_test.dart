import 'dart:async';
import 'dart:io';

import 'package:glados/glados.dart';
import 'package:muster/src/model/clone_path.dart';
import 'package:muster/src/model/commit.dart';
import 'package:muster/src/store/cache.dart';
import 'package:muster/src/store/claims.dart';
import 'package:path/path.dart' as p;

import '../support/git.dart';
import '../support/origin.dart';
import '../support/spy_runner.dart';

/// How a ref off the default branch holds its commits.
enum _Ref { branch, lightweightTag, annotatedTag }

/// A line of commits off the default branch: the ref that holds its tip, the
/// commit it grows from, drawn among those made before it or none, and how
/// many commits it adds.
typedef _Side = ({_Ref ref, int base, int length});

/// A repo's history: how many commits `main` holds, and the lines off it.
typedef _Shape = ({int main, List<_Side> sides});

/// A repo's history, a draw of which of its commits a test pins, and whether
/// the cache already holds a clone made before the lines off `main`, so the
/// pin is reached by a fetch rather than the clone's first copy.
typedef _Draw = ({_Shape shape, int first, int second, bool warm});

final Generator<_Side> _side = any.combine3(
  any.choose(_Ref.values),
  any.intInRange(0, 8),
  any.intInRange(1, 4),
  (_Ref ref, int base, int length) => (ref: ref, base: base, length: length),
);

final Generator<_Draw> _draw = any.combine5(
  any.intInRange(1, 4),
  any.listWithLengthInRange(1, 4, _side),
  any.intInRange(0, 8),
  any.intInRange(0, 8),
  any.bool,
  (int main, List<_Side> sides, int first, int second, bool warm) => (
    shape: (main: main, sides: sides),
    first: first,
    second: second,
    warm: warm,
  ),
);

/// `main`'s commits of [shape], made in [origin].
Future<List<Commit>> _main(Origin origin, _Shape shape) async {
  final List<Commit> main = [];
  for (int i = 0; i < shape.main; i++) {
    main.add(await origin.commit(main.lastOrNull));
  }
  await origin.ref('refs/heads/main', main.last);
  return main;
}

/// The lines off [main] of [shape], made in [origin]: the commits only a ref
/// off `main` reaches.
Future<List<Commit>> _off(
  Origin origin,
  _Shape shape,
  List<Commit> main,
) async {
  final List<Commit> off = [];
  for (final (int i, _Side side) in shape.sides.indexed) {
    final List<Commit> before = [...main, ...off];
    // One draw past the commits made so far grows the line from no commit.
    final int at = side.base % (before.length + 1);
    Commit? tip = at == before.length ? null : before[at];
    for (int n = 0; n < side.length; n++) {
      tip = await origin.commit(tip);
      off.add(tip);
    }
    switch (side.ref) {
      case .branch:
        await origin.ref('refs/heads/side$i', tip!);
      case .lightweightTag:
        await origin.tag('t$i', tip!, annotated: false);
      case .annotatedTag:
        await origin.tag('t$i', tip!, annotated: true);
    }
  }
  return off;
}

final ExploreConfig _explore = .new(numRuns: 40);

/// Temporary clones left in the cache before a clone: whether the clone's
/// own URL left one, and for each other URL, whether a hold has its claim.
typedef _Left = ({bool own, List<bool> held});

final Generator<_Left> _left = any.combine2(
  any.bool,
  any.listWithLengthInRange(0, 5, any.bool),
  (bool own, List<bool> held) => (own: own, held: held),
);

void main() {
  Glados(_draw, _explore).test(
    'A pin reachable only from a branch or tag that isn\'t the default branch '
    'is still reached.',
    (_Draw draw) => inTemp((Directory temp) async {
      final SpyRunner runner = .new(hermetic(temp));
      final Origin origin = await .make(temp, runner);
      final Cache cache = cacheIn(temp, runner);
      final List<Commit> main = await _main(origin, draw.shape);
      if (draw.warm) {
        await cache.clone(origin.url, main.last);
      }
      final List<Commit> off = await _off(origin, draw.shape, main);
      final Commit pin = off[draw.first % off.length];
      final ClonePath clone = await cache.clone(origin.url, pin);
      expect(await holds(clone.path, pin, runner), isTrue);
    }),
  );

  Glados(_draw, _explore).test(
    'A clone that already holds the pin\'s commit is never fetched.',
    (_Draw draw) => inTemp((Directory temp) async {
      final SpyRunner runner = .new(hermetic(temp));
      final Origin origin = await .make(temp, runner);
      final List<Commit> main = await _main(origin, draw.shape);
      final List<Commit> all = [
        ...main,
        ...await _off(origin, draw.shape, main),
      ];
      final Commit first = all[draw.first % all.length];
      final Commit second = all[draw.second % all.length];
      await cacheIn(temp, runner).clone(origin.url, first);
      // A commit the origin gains after the fetch, so a fetch would bring
      // something.
      await origin.ref('refs/heads/main', await origin.commit(main.last));
      runner.commands.clear();
      await cacheIn(temp, runner).clone(origin.url, second);
      expect(runner.fetched, isFalse);
    }),
  );

  Glados(_left, .new(numRuns: 20)).test(
    'A clone removes every temporary clone in the cache whose claim no hold '
    'has, and leaves every one whose claim is held.',
    (_Left left) => inTemp((Directory temp) async {
      final SpyRunner runner = .new(hermetic(temp));
      final Origin origin = await .make(temp, runner);
      final Cache cache = cacheIn(temp, runner);
      final Commit pin = await origin.commit();
      await origin.ref('refs/heads/main', pin);
      final List<ClonePath> others = [
        for (int i = 0; i < left.held.length; i++)
          .of(cache.directory, .parse('https://example.com/$i.git')!),
      ];
      for (final ClonePath clone in [
        if (left.own) ClonePath.of(cache.directory, origin.url),
        ...others,
      ]) {
        await File(p.join(clone.temporary.path, 'HEAD'))
            .create(recursive: true);
      }
      final Completer<void> go = .new();
      final List<Future<void>> holders = [];
      for (final (int i, bool held) in left.held.indexed) {
        if (held) {
          final Completer<void> taken = .new();
          holders.add(
            Claims(.posix).holding(others[i].claim, () {
              taken.complete();
              return go.future;
            }),
          );
          await taken.future;
        }
      }
      await cache.clone(origin.url, pin);
      final List<String> standing = [
        await for (final FileSystemEntity entity in Directory(
          cache.directory.path,
        ).list())
          if (entity.path.endsWith('.partial')) p.basename(entity.path),
      ];
      expect(
        standing,
        unorderedEquals([
          for (final (int i, bool held) in left.held.indexed)
            if (held) p.basename(others[i].temporary.path),
        ]),
      );
      go.complete();
      await Future.wait(holders);
    }),
  );
}

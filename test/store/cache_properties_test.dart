import 'dart:async';
import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/src/model/cache_directory.dart';
import 'package:muster/src/model/clone_path.dart';
import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/git_url.dart';
import 'package:muster/src/store/cache.dart';
import 'package:muster/src/store/claims.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/locker.dart';
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

/// Another URL's temporary clone in the cache: whether a hold has its
/// claim, and whether it is the tokenless `<hash>.partial`.
typedef _Other = ({bool held, bool bare});

/// A line of commits off the default branch, its base any of the commits
/// made before it or none, and one to three commits long.
final Gen<_Side> _side = .build(
  (Draw draw) => (
    ref: draw(.element(_Ref.values)),
    base: draw(.integer(min: 0, max: 7)),
    length: draw(.integer(min: 1, max: 3)),
  ),
);

/// A repo's history: one to three commits on `main`, and one to three lines
/// off it.
final Gen<_Shape> _shape = .build(
  (Draw draw) => (
    main: draw(.integer(min: 1, max: 3)),
    sides: draw(.list(_side, minLength: 1, maxLength: 3)),
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

/// The search of a property drawing a history and the commits it pins.
final Settings _explore = .new(runs: 40, shrinkSteps: gitShrinks);

void main() {
  property(
    "STO-10: A pin reachable only from a branch or tag that isn't the default "
    'branch is still reached.',
    (Draw draw) async {
      final _Shape shape = draw(_shape, label: 'shape');
      final int first = draw(.integer(min: 0, max: 7), label: 'first');
      // Whether the cache already holds a clone made before the lines off
      // `main`, so the pin is reached by a fetch rather than the clone's
      // first copy.
      final bool warm = draw(.boolean(), label: 'warm');
      await inTemp((Directory temp) async {
        final SpyRunner runner = .new(hermetic(temp));
        final Origin origin = await .make(temp, runner);
        final Cache cache = cacheIn(temp, runner);
        final List<Commit> main = await _main(origin, shape);
        if (warm) {
          await cache.clone(origin.url, main.last);
        }
        final List<Commit> off = await _off(origin, shape, main);
        final Commit pin = off[first % off.length];
        final ClonePath clone = await cache.clone(origin.url, pin);
        expect(await holds(clone.path, pin, runner), isTrue);
      });
    },
    settings: _explore,
  );

  property("STO-15: A clone that already holds the pin's commit is never "
      'fetched.', (Draw draw) async {
    final _Shape shape = draw(_shape, label: 'shape');
    final int firstAt = draw(.integer(min: 0, max: 7), label: 'firstAt');
    final int secondAt = draw(.integer(min: 0, max: 7), label: 'secondAt');
    await inTemp((Directory temp) async {
      final SpyRunner runner = .new(hermetic(temp));
      final Origin origin = await .make(temp, runner);
      final List<Commit> main = await _main(origin, shape);
      final List<Commit> all = [...main, ...await _off(origin, shape, main)];
      final Commit first = all[firstAt % all.length];
      final Commit second = all[secondAt % all.length];
      await cacheIn(temp, runner).clone(origin.url, first);
      // A commit the origin gains after the fetch, so a fetch would bring
      // something.
      await origin.ref('refs/heads/main', await origin.commit(main.last));
      runner.commands.clear();
      await cacheIn(temp, runner).clone(origin.url, second);
      expect(runner.fetched, isFalse);
    });
  }, settings: _explore);

  property('STO-21: A clone: removes every temporary clone in the cache whose '
      'claim no other hold has, leaves every one whose claim is held, '
      'never waiting on it, leaves every entry that is no temporary '
      'clone.', (Draw draw) async {
    final bool own = draw(.boolean(), label: 'own');
    // Whether the cache holds the clone already, so the call finds it
    // standing rather than making it.
    final bool warm = draw(.boolean(), label: 'warm');
    final bool ownBare = draw(.boolean(), label: 'ownBare');
    final List<_Other> others = draw(
      .list(
        .build((Draw draw) => (held: draw(.boolean()), bare: draw(.boolean()))),
        maxLength: 4,
      ),
      label: 'others',
    );
    final Set<int> strays = draw(
      .set(.integer(min: 0, max: 3)),
      label: 'strays',
    );
    await inTemp((Directory temp) async {
      final SpyRunner runner = .new(hermetic(temp));
      final Origin origin = await .make(temp, runner);
      final Cache cache = cacheIn(
        temp,
        runner,
        .new(testLocker, () async => fail('a held claim was waited on')),
      );
      final Commit pin = await origin.commit();
      await origin.ref('refs/heads/main', pin);
      if (warm) {
        await cache.clone(origin.url, pin);
      }
      final List<GitUrl> otherUrls = [
        for (int i = 0; i < others.length; i++)
          .parse('https://example.com/$i.git')!,
      ];
      final List<String> leftOthers = [
        for (final (int i, _Other other) in others.indexed)
          _leftFor(cache.directory, otherUrls[i], bare: other.bare),
      ];
      final List<String> strayPool = _strays(cache.directory);
      final List<String> strayNames = [
        for (final int i in strays) strayPool[i],
      ];
      for (final String name in [
        if (own) _leftFor(cache.directory, origin.url, bare: ownBare),
        ...leftOthers,
        ...strayNames,
      ]) {
        await File(p.join(cache.directory.path, name, 'HEAD'))
            .create(recursive: true);
      }
      final Completer<void> go = .new();
      final List<Future<void>> holders = [];
      for (final (int i, _Other other) in others.indexed) {
        if (other.held) {
          final Completer<void> taken = .new();
          holders.add(
            Claims(testLocker)
                .holding(ClonePath.of(cache.directory, otherUrls[i]).claim, () {
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
          p.basename(entity.path),
      ];
      expect(
        standing.where(
          (String name) => ClonePath.ofTemporary(cache.directory, name) != null,
        ),
        unorderedEquals([
          for (final (int i, _Other other) in others.indexed)
            if (other.held) leftOthers[i],
        ]),
      );
      expect(standing, containsAll(strayNames));
      go.complete();
      await Future.wait(holders);
    });
  }, settings: .new(runs: 20, shrinkSteps: gitShrinks));
}

/// The name of a temporary clone of [url]'s in [cache], as a make cut short
/// leaves one: with a token, or `<hash>.partial` with none where [bare].
String _leftFor(CacheDirectory cache, GitUrl url, {required bool bare}) => bare
    ? '${p.basename(ClonePath.of(cache, url).path)}.partial'
    : '${ClonePath.temporaryPrefix(url)}left';

/// Entries of [cache] that are no temporary clone: another URL's clone, a
/// name ending `.partial` with no clone's hash before it, a name of no
/// clone's, and a clone's hash followed by more than `.partial`.
List<String> _strays(CacheDirectory cache) {
  final String hash = p.basename(
    ClonePath.of(cache, .parse('https://example.com/stray.git')!).path,
  );
  return [hash, 'notes.partial', '.clone-abc123', '$hash.partialx'];
}

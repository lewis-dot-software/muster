import 'dart:io';

import 'package:glados/glados.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:path/path.dart' as p;

import '../support/files_under.dart';
import '../support/git.dart';
import '../support/loads.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/scratches.dart';
import '../support/shrinking_at_most.dart';
import '../support/spy_runner.dart';
import '../support/tree_under.dart';
import '../support/write_file.dart';

/// The files a commit may hold beside its package's, each drawn or not.
const List<String> _pool = ['lib/a.dart', 'lib/b/c.dart', 'README.md'];

/// What every commit's `.gitignore` ignores: `.dart_tool/` and `ignored/`.
const String _gitignore = '.dart_tool/\nignored/\n';

/// What a consumer does to its scratch before a move.
enum _Dirt {
  /// Nothing.
  none,

  /// A tracked file's contents rewritten.
  editTracked,

  /// An untracked file written.
  addUntracked,

  /// A file the `.gitignore` ignores written.
  addIgnored,
}

/// The commits of a history, each the files of [_pool] it holds, the index
/// of the pin among them, and each move: the index of its commit and what
/// the consumer does to the scratch before it.
typedef _Draw = ({List<Set<int>> history, int pin, List<(int, _Dirt)> moves});

final Generator<_Draw> _draw = any
    .combine3(
      any.listWithLengthInRange(2, 5, any.set(any.intInRange(0, _pool.length))),
      any.intInRange(0, 5),
      any.listWithLengthInRange(
        1,
        5,
        any.combine2(
          any.intInRange(0, 5),
          any.choose(_Dirt.values),
          (int at, _Dirt dirt) => (at, dirt),
        ),
      ),
      (List<Set<int>> history, int pin, List<(int, _Dirt)> moves) =>
          (history: history, pin: pin, moves: moves),
    )
    .shrinkingAtMost(gitTries);

/// The files of the commit at [index] of a history, holding the package
/// `app`, the `.gitignore` and the files of [_pool] at [pool].
Map<String, String> _commitFiles(int index, Set<int> pool) => {
  ...packageFiles('app'),
  '.gitignore': _gitignore,
  for (final int i in pool) _pool[i]: 'file $i of commit $index\n',
};

/// A fault that keeps a scratch from being made.
enum _Fault {
  /// A name no codebase of the load bears.
  notNamed,

  /// No git on `PATH`.
  unstartable,

  /// A pin on none of its URL's branches or tags.
  pinMissing,

  /// A URL that is no repo.
  notARepo,

  /// A cache that is a file.
  cacheBlocked,

  /// A temporary directory that is a file.
  tempBlocked,
}

void main() {
  Glados(_draw, ExploreConfig(numRuns: 10)).test(
    'A scratch worktree moves to any commit in its clone without touching '
    "any consumer's checkout, and is gone once it is disposed of.",
    (_Draw draw) async {
      await inTemp((Directory temp) async {
        final SpyRunner runner = .new(hermetic(temp));
        final Origin origin = await .make(temp, runner);
        final List<Commit> commits = [];
        Commit? parent;
        for (int i = 0; i < draw.history.length; i++) {
          parent = await origin.commit(
            parent,
            _commitFiles(i, draw.history[i]),
          );
          commits.add(parent);
        }
        await origin.ref('refs/heads/main', commits.last);
        final int pin = draw.pin % commits.length;
        final GitCodebase app = codebaseOf(origin, commits[pin]);
        final String manifest = atRoot(temp);
        await writeManifest(manifest, [app]);
        final List<String> roots = [
          consumerIn(temp).path,
          p.join(temp.path, 'other'),
        ];
        Future<Load> loadAt(String root) =>
            loaderIn(temp, runner, root: root).load(named: [manifest]);
        Muster? muster;
        for (final String root in roots) {
          final Load load = await loadAt(root);
          expect(load, loadedWith({'app': isA<Fetched>()}));
          muster ??= (load as Loaded).muster;
        }
        final Map<String, Map<String, String>> before = {
          for (final String root in roots) root: await treeUnder(root),
        };
        final Scratching made = await muster!.scratch(app.name);
        final Scratch scratch = switch (made) {
          Scratched(:final Scratch scratch) => scratch,
          NotNamed() || ScratchFailed() => fail('$made'),
        };
        final String at = scratch.package.path;
        for (final (int index, _Dirt dirt) in draw.moves) {
          switch (dirt) {
            case .none:
              break;
            case .editTracked:
              await File(p.join(at, 'pubspec.yaml')).writeAsString('edited');
            case .addUntracked:
              await writeFile(p.join(at, 'stray', 'a.txt'), 'stray');
            case .addIgnored:
              await writeFile(p.join(at, 'ignored', 'a.txt'), 'ignored');
          }
          final int to = index % commits.length;
          expect(await scratch.move(commits[to]), isA<Moved>());
          expect(await headOf(at, runner), commits[to].hash);
          expect(await filesUnder(at), _commitFiles(to, draw.history[to]));
          for (final String root in roots) {
            expect(await treeUnder(root), before[root], reason: root);
          }
        }
        expect(await scratch.dispose(), isA<Disposed>());
        expect(await Directory(at).exists(), isFalse);
        expect(await scratchesLeft(temp), isEmpty);
        expect(
          (await worktreesOf(cloneOf(temp, app), runner))..sort(),
          [
            for (final String root in roots)
              await Directory(p.join(root, '.dart_tool', 'muster', 'app'))
                  .resolveSymbolicLinks(),
          ]..sort(),
        );
        for (final String root in roots) {
          expect(await treeUnder(root), before[root], reason: root);
          runner.commands.clear();
          expect(await loadAt(root), loadedWith({'app': isA<Fetched>()}));
          expect(runner.given, isNot(contains(contains('worktree add'))));
          expect(runner.given, isNot(contains(contains('checkout'))));
        }
      });
    },
  );

  Glados2(
    any.choose(_Fault.values).shrinkingAtMost(gitTries),
    any.lowercaseLetters.shrinkingAtMost(gitTries),
    ExploreConfig(numRuns: 18),
  ).test('A scratch that cannot be made comes back as an outcome, never a '
      'throw.', (_Fault fault, String letters) async {
    await inTemp((Directory temp) async {
      final SpyRunner runner = .new(hermetic(temp));
      final Origin origin = await .make(temp, runner);
      final Commit commit = await origin.commit(null, packageFiles('app'));
      switch (fault) {
        case .pinMissing:
          break;
        case .notNamed ||
            .unstartable ||
            .notARepo ||
            .cacheBlocked ||
            .tempBlocked:
          await origin.ref('refs/heads/main', commit);
      }
      final GitCodebase app = codebaseOf(origin, commit);
      await writeManifest(atRoot(temp), [
        switch (fault) {
          .notARepo => (
            name: app.name,
            url: .parse(p.join(temp.path, 'nowhere'))!,
            commit: app.commit,
            root: app.root,
            toolchain: app.toolchain,
          ),
          .notNamed ||
          .unstartable ||
          .pinMissing ||
          .cacheBlocked ||
          .tempBlocked => app,
        },
      ]);
      final String blocked = p.join(temp.path, 'blocked');
      await File(blocked).writeAsString('');
      switch (fault) {
        case .tempBlocked:
          await File(scratchesIn(temp).path).writeAsString('');
        case .notNamed ||
            .unstartable ||
            .pinMissing ||
            .notARepo ||
            .cacheBlocked:
          break;
      }
      final Load load = await loaderIn(
        temp,
        switch (fault) {
          .unstartable => unstartableIn(temp),
          .notNamed ||
          .pinMissing ||
          .notARepo ||
          .cacheBlocked ||
          .tempBlocked => runner,
        },
        variables: switch (fault) {
          .cacheBlocked => {'MUSTER_CACHE': blocked},
          .notNamed ||
          .unstartable ||
          .pinMissing ||
          .notARepo ||
          .tempBlocked => const {},
        },
      ).load();
      final Muster muster = (load as Loaded).muster;
      final CodebaseName name = switch (fault) {
        .notNamed => .parse('x$letters')!,
        .unstartable ||
        .pinMissing ||
        .notARepo ||
        .cacheBlocked ||
        .tempBlocked => app.name,
      };
      final Scratching made = await muster.scratch(name);
      expect(made, switch (fault) {
        .notNamed => isA<NotNamed>().having(
          (NotNamed n) => n.name,
          'name',
          name,
        ),
        .unstartable => _failedWith(isA<Unstartable>()),
        .pinMissing => _failedWith(isA<PinMissing>()),
        .notARepo => _failedWith(isA<CommandFailed>()),
        .cacheBlocked || .tempBlocked => _failedWith(isA<StoreFailed>()),
      });
      switch (fault) {
        case .tempBlocked:
          break;
        case .notNamed ||
            .unstartable ||
            .pinMissing ||
            .notARepo ||
            .cacheBlocked:
          expect(await scratchesLeft(temp), isEmpty);
      }
    });
  });
}

/// Matches a scratch that failed for a failure [failure] matches.
Matcher _failedWith(Matcher failure) => isA<ScratchFailed>().having(
  (ScratchFailed s) => s.failure,
  'failure',
  failure,
);

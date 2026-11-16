import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/files_under.dart';
import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/manifests.dart';
import '../support/origin.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
import '../support/scratches.dart';
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
  property(
    'A scratch worktree moves to any commit in its clone without touching '
    "any consumer's checkout, and is gone once it is disposed of.",
    (Draw draw) async {
      final List<Set<int>> history = draw(
        .list(
          .set(.integer(min: 0, max: _pool.length - 1)),
          minLength: 2,
          maxLength: 4,
        ),
        label: 'history',
      );
      final int pin = draw(
        .integer(min: 0, max: history.length - 1),
        label: 'pin',
      );
      final List<(int commit, _Dirt dirt)> moves = draw(
        .list(
          .build(
            (Draw draw) => (
              draw(.integer(min: 0, max: history.length - 1)),
              draw(.element(_Dirt.values)),
            ),
          ),
          minLength: 1,
          maxLength: 4,
        ),
        label: 'moves',
      );
      await inTemp((Directory temp) async {
        final SpyRunner runner = .new(hermetic(temp));
        final Origin origin = await .make(temp, runner);
        final List<Commit> commits = [];
        Commit? parent;
        for (int i = 0; i < history.length; i++) {
          parent = await origin.commit(parent, _commitFiles(i, history[i]));
          commits.add(parent);
        }
        await origin.ref('refs/heads/main', commits.last);
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
          NotNamed() || NotGit() || ScratchFailed() => fail('$made'),
        };
        final String at = scratch.package.path;
        for (final (int to, _Dirt dirt) in moves) {
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
          expect(await scratch.move(commits[to]), isA<Moved>());
          expect(await headOf(at, runner), commits[to].hash);
          expect(await filesUnder(at), _commitFiles(to, history[to]));
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
    settings: .new(runs: 10, shrinkSteps: gitShrinks),
  );

  property('A scratch that cannot be made comes back as an outcome, never a '
      'throw.', (Draw draw) async {
    final _Fault fault = draw(.element(_Fault.values), label: 'fault');
    final String letters = draw(
      .string(alphabet: .lowerCase),
      label: 'letters',
    );
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
  }, settings: .new(runs: 18, shrinkSteps: gitShrinks));

  property('A scratch asked of a hosted codebase gives `NotGit` and starts no '
      'process.', (Draw draw) async {
    final List<bool> hosted = draw(
      .list(.boolean(), minLength: 1),
      label: 'hosted',
    );
    final List<int> asks = draw(
      .list(.integer(min: 0, max: 5), minLength: 1),
      label: 'asks',
    );
    await inTemp((Directory temp) async {
      // A server serving nothing, so no unpack reaches pub.dev.
      final PackageServer server = await .start();
      try {
        final SpyRunner runner = .new({
          ...hermetic(temp),
          ...pubVariables(temp, server),
        });
        final Origin origin = await .make(temp, runner);
        final Commit commit = await origin.commit(null, packageFiles('app'));
        await origin.ref('refs/heads/main', commit);
        final List<Entry> entries = [];
        final List<CodebaseName> hostedNames = [];
        for (final (int i, bool isHosted) in hosted.take(4).indexed) {
          if (isHosted) {
            entries.add(hostedEntryOf(hostedOf('p$i', name: 'c$i')));
            hostedNames.add(.parse('c$i')!);
          } else {
            entries.add(entryOf(codebaseOf(origin, commit, name: 'c$i')));
          }
        }
        await writeFile(atRoot(temp), renderManifest(entries));
        final Muster muster = switch (await loaderIn(temp, runner).load()) {
          Loaded(:final Muster muster) => muster,
          Refused(:final LoadRefusal reason) => fail('refused: $reason'),
        };
        for (final int ask in hostedNames.isEmpty ? <int>[] : asks.take(4)) {
          final CodebaseName name = hostedNames[ask % hostedNames.length];
          final int before = runner.commands.length;
          expect(
            await muster.scratch(name),
            isA<NotGit>().having((NotGit n) => n.name, 'name', name),
          );
          expect(runner.commands, hasLength(before), reason: '$name');
        }
        expect(await scratchesLeft(temp), isEmpty);
      } finally {
        await server.close();
      }
    });
  }, settings: .new(runs: 10, shrinkSteps: gitShrinks));
}

/// Matches a scratch that failed for a failure [failure] matches.
Matcher _failedWith(Matcher failure) => isA<ScratchFailed>().having(
  (ScratchFailed s) => s.failure,
  'failure',
  failure,
);

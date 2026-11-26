import 'dart:async';
import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/store/store_fault.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/apart.dart';
import '../support/chmod.dart';
import '../support/contender.dart';
import '../support/files_under.dart';
import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/manifests.dart';
import '../support/origin.dart';
import '../support/outcome_case.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
import '../support/scratches.dart';
import '../support/skipped_unless_modes_deny.dart';
import '../support/spy_runner.dart';
import '../support/tree_under.dart';
import '../support/waiting_into.dart';
import '../support/write_file.dart';

/// The files a commit may hold beside its package's, each drawn or not.
const List<String> _pool = ['lib/a.dart', 'lib/b/c.dart', 'README.md'];

/// What every commit's `.gitignore` ignores: `.dart_tool/` and `ignored/`.
const String _gitignore = '.dart_tool/\nignored/\n';

/// A move of a scratch: the index of the `commit` it moves to, and the
/// `dirt` the consumer leaves in it before.
typedef _Move = (int commit, _Dirt dirt);

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

/// What a codebase's load gave before its scratch is asked for.
enum _Gave {
  /// `Fetched`.
  fetched,

  /// `Unlocked`, its commit holding no lock and none kept.
  unlocked,

  /// `CommandFailed`, its resolve failing on a path dependency that is not
  /// there.
  resolveFailed,

  /// `PinMissing`, its pin on no ref until the load is done.
  pinMissing,
}

/// The files of a commit holding the package `app`, which its load gives
/// as [gave] says.
Map<String, String> _gaveFiles(_Gave gave) => switch (gave) {
  .fetched || .pinMissing => packageFiles('app'),
  .unlocked => packageFiles('app', locked: false),
  .resolveFailed => {
    ...packageFiles('app'),
    'pubspec.yaml':
        '${pubspecOf('app')}dependencies:\n  gone:\n    path: gone\n',
  },
};

/// The case of the outcome a load gives a codebase as [gave] says.
OutcomeCase _caseOf(_Gave gave) => switch (gave) {
  .fetched => .fetched,
  .unlocked => .unlocked,
  .resolveFailed => .commandFailed,
  .pinMissing => .pinMissing,
};

/// A scratch's act, each of which takes its clone's claim.
enum _Act {
  /// Its make.
  make,

  /// A move to a commit its clone lacks, which fetches it.
  move,

  /// Its disposal, which prunes its clone's record of it.
  dispose,
}

/// The act that fails in a scratch whose make cannot be undone.
enum _Failing {
  /// git cannot start.
  unstartable,

  /// The pin is on none of its URL's branches or tags.
  pinMissing,

  /// The worktree's add, into a directory that is not empty.
  worktreeAdd,
}

void main() {
  property(
    'LOA-7: A scratch worktree moves to any commit of its URL\'s, fetching '
    "one its clone lacks, without touching any consumer's checkout, and is "
    "gone with its clone's record of it once disposed of, a second disposal "
    'giving `Disposed` too.',
    (Draw draw) async {
      final List<Set<int>> history = draw(
        .list(
          .set(.integer(min: 0, max: _pool.length - 1)),
          minLength: 2,
          maxLength: 4,
        ),
        label: 'history',
      );
      final int published = draw(
        .integer(min: 1, max: history.length),
        label: 'published',
      );
      final int pin = draw(.integer(min: 0, max: published - 1), label: 'pin');
      final List<_Move> moves = draw(
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
        // The commits past the published ones are on no ref until the
        // scratch is made, so its clone lacks them.
        await origin.ref('refs/heads/main', commits[published - 1]);
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
        if (published < commits.length) {
          await origin.ref('refs/heads/later', commits.last);
        }
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

  property('LOA-8: A scratch that cannot be made comes back as `NotNamed`, '
      'starting no process, or as `ScratchFailed` for the act that failed, '
      'leaving no directory behind, never as a throw.', (Draw draw) async {
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
      final int before = runner.commands.length;
      final Scratching made = await muster.scratch(name);
      switch (fault) {
        case .notNamed:
          expect(runner.commands, hasLength(before));
        case .unstartable ||
            .pinMissing ||
            .notARepo ||
            .cacheBlocked ||
            .tempBlocked:
          break;
      }
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

  property('LOA-12: A scratch asked of a hosted codebase gives `NotGit` and '
      'starts no process.', (Draw draw) async {
    final List<bool> hosted = draw(
      .list(.boolean(), minLength: 1),
      label: 'hosted',
    );
    final int forced = draw(.integer(min: 0, max: 3), label: 'forced');
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
        final List<bool> taken = hosted.take(4).toList();
        for (final (int i, bool drawn) in taken.indexed) {
          if (drawn || i == forced % taken.length) {
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
        for (final int ask in asks.take(4)) {
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

  property(
    "LOA-14: A scratch is made at its pin, holding the pin's files, whatever "
    "its codebase's load gave and whether its clone was deleted since.",
    (Draw draw) async {
      final _Gave gave = draw(.element(_Gave.values), label: 'gave');
      final bool deleted = draw(.boolean(), label: 'deleted');
      await inTemp((Directory temp) async {
        final SpyRunner runner = .new(hermetic(temp));
        final Origin origin = await .make(temp, runner);
        final Map<String, String> files = _gaveFiles(gave);
        final Commit pin = await origin.commit(null, files);
        switch (gave) {
          case .pinMissing:
            break;
          case .fetched || .unlocked || .resolveFailed:
            await origin.ref('refs/heads/main', pin);
        }
        final GitCodebase app = codebaseOf(origin, pin);
        await writeManifest(atRoot(temp), [app]);
        final Load load = await loaderIn(temp, runner).load();
        final Muster muster = switch (load) {
          Loaded(:final Muster muster, :final outcomes) =>
            OutcomeCase.of(outcomes[app.name]!) == _caseOf(gave)
                ? muster
                : fail('${gave.name}: ${outcomes[app.name]}'),
          Refused(:final LoadRefusal reason) => fail('refused: $reason'),
        };
        switch (gave) {
          case .pinMissing:
            await origin.ref('refs/heads/main', pin);
          case .fetched || .unlocked || .resolveFailed:
            break;
        }
        final Directory clone = .new(cloneOf(temp, app).path);
        if (deleted && await clone.exists()) {
          await clone.delete(recursive: true);
        }
        final Scratching made = await muster.scratch(app.name);
        final Scratch scratch = switch (made) {
          Scratched(:final Scratch scratch) => scratch,
          NotNamed() || NotGit() || ScratchFailed() => fail('$made'),
        };
        expect(await headOf(scratch.package.path, runner), pin.hash);
        expect(await filesUnder(scratch.package.path), files);
        expect(await scratch.dispose(), isA<Disposed>());
      });
    },
    settings: .new(runs: 12, shrinkSteps: gitShrinks),
  );

  property(
    "LOA-15: A move to a commit on none of its URL's branches or tags gives "
    '`MoveFailed` for `PinMissing`, naming that commit, the scratch left at '
    'the commit it was at and no checkout touched.',
    (Draw draw) async {
      final List<bool> strays = draw(
        .list(.boolean(), minLength: 1, maxLength: 4),
        label: 'strays',
      );
      await inTemp((Directory temp) async {
        final SpyRunner runner = .new(hermetic(temp));
        final Origin origin = await .make(temp, runner);
        final Commit pin = await origin.commit(null, _commitFiles(0, {}));
        final Commit next = await origin.commit(pin, _commitFiles(1, {0}));
        await origin.ref('refs/heads/main', next);
        final GitCodebase app = codebaseOf(origin, pin);
        await writeManifest(atRoot(temp), [app]);
        final Muster muster = switch (await loaderIn(temp, runner).load()) {
          Loaded(:final Muster muster) => muster,
          Refused(:final LoadRefusal reason) => fail('refused: $reason'),
        };
        final Map<String, String> before = await treeUnder(
          consumerIn(temp).path,
        );
        final Scratch scratch = switch (await muster.scratch(app.name)) {
          Scratched(:final Scratch scratch) => scratch,
          final Scratching made &&
              (NotNamed() || NotGit() || ScratchFailed()) =>
            fail('$made'),
        };
        final String at = scratch.package.path;
        Commit was = pin;
        for (final (int i, bool stray) in strays.indexed) {
          if (stray) {
            // A commit of the origin's that no ref reaches.
            final Commit lost = await origin.commit(was, {'lost$i.txt': ''});
            final Map<String, String> held = await filesUnder(at);
            expect(
              await scratch.move(lost),
              isA<MoveFailed>().having(
                (MoveFailed m) => m.failure,
                'failure',
                isA<PinMissing>().having(
                  (PinMissing m) => m.commit,
                  'commit',
                  lost,
                ),
              ),
            );
            expect(await headOf(at, runner), was.hash);
            expect(await filesUnder(at), held);
          } else {
            was = was == pin ? next : pin;
            expect(await scratch.move(was), isA<Moved>());
          }
          expect(await treeUnder(consumerIn(temp).path), before);
        }
        expect(await scratch.dispose(), isA<Disposed>());
      });
    },
    settings: .new(runs: 8, shrinkSteps: gitShrinks),
  );

  property(
    "LOA-16: A scratch's make, move and disposal each wait on a load's claim "
    'on its clone, in an isolate or a process of its own, running no command '
    'until the load lets it go.',
    (Draw draw) async {
      for (final Apart apart in Apart.values) {
        for (final _Act act in _Act.values) {
          await _waitOnLoad(apart, act);
        }
      }
    },
    settings: .new(runs: 1),
  );

  property(
    'LOA-17: A `ScratchFailed` whose directory cannot be removed leaves that '
    'directory in the temporary directory, carrying the failure of the act '
    'that failed and throwing nothing.',
    (Draw draw) async {
      final _Failing failing = draw(
        .element(_Failing.values),
        label: 'failing',
      );
      await inTemp((Directory temp) async {
        if (await skippedUnlessModesDeny(temp)) {
          return;
        }
        final SpyRunner runner = .new(hermetic(temp));
        final Origin origin = await .make(temp, runner);
        final Commit pin = await origin.commit(null, packageFiles('app'));
        switch (failing) {
          case .pinMissing:
            break;
          case .unstartable || .worktreeAdd:
            await origin.ref('refs/heads/main', pin);
        }
        final GitCodebase app = codebaseOf(origin, pin);
        await writeManifest(atRoot(temp), [app]);
        final Muster muster = switch (await loaderIn(temp, runner).load()) {
          Loaded(:final Muster muster) => muster,
          Refused(:final LoadRefusal reason) => fail('refused: $reason'),
        };
        Directory? locked;
        // The scratch's directory is made before its first command, so a
        // directory written into it then, its mode denying its removal,
        // keeps it from being removed.
        runner.before = (Command command) async {
          if (locked == null) {
            final List<String> made = await scratchesLeft(temp);
            locked = await .new(p.join(made.single, 'locked')).create();
            await File(p.join(locked!.path, 'kept.txt')).writeAsString('');
            await chmod('500', locked!);
          }
          switch (failing) {
            case .unstartable:
              throw const StoreFault(Unstartable(.git));
            case .pinMissing || .worktreeAdd:
              break;
          }
        };
        try {
          expect(
            await muster.scratch(app.name),
            _failedWith(switch (failing) {
              .unstartable => isA<Unstartable>(),
              .pinMissing => isA<PinMissing>(),
              .worktreeAdd => isA<CommandFailed>(),
            }),
          );
          final List<String> left = await scratchesLeft(temp);
          expect(left, hasLength(1));
          expect(
            await File(p.join(left.single, 'locked', 'kept.txt')).exists(),
            isTrue,
          );
        } finally {
          if (locked case final Directory directory) {
            await chmod('700', directory);
          }
        }
      });
    },
    settings: .new(runs: 6, shrinkSteps: gitShrinks),
  );
}

/// A scratch's [act] while a load [apart] holds its clone's claim, paused at
/// its first command on the clone, asserting it runs no command until the
/// load lets the claim go, and then succeeds.
Future<void> _waitOnLoad(Apart apart, _Act act) => inTemp((
  Directory temp,
) async {
  final String at = 'apart ${apart.name}, act ${act.name}';
  final SpyRunner runner = .new(hermetic(temp));
  final Origin origin = await .make(temp, runner);
  final Commit pin = await origin.commit(null, packageFiles('app'));
  final Commit later = await origin.commit(pin, packageFiles('app'));
  await origin.ref('refs/heads/main', pin);
  final GitCodebase app = codebaseOf(origin, pin);
  final String manifest = atRoot(temp);
  await writeManifest(manifest, [app]);
  final Completer<void> waiting = .new();
  final Muster muster = switch (await loaderIn(
    temp,
    runner,
    claims: waitingInto(waiting),
  ).load()) {
    Loaded(:final Muster muster) => muster,
    Refused(:final LoadRefusal reason) => fail('refused: $reason'),
  };
  final Scratch? scratch = switch (act) {
    .make => null,
    .move || .dispose => switch (await muster.scratch(app.name)) {
      Scratched(:final Scratch scratch) => scratch,
      final Scratching made && (NotNamed() || NotGit() || ScratchFailed()) =>
        fail('$at: $made'),
    },
  };
  switch (act) {
    case .move:
      // The clone lacks it until the move fetches it.
      await origin.ref('refs/heads/later', later);
    case .make || .dispose:
      break;
  }
  final String other = p.join(temp.path, 'other');
  final Contender load = await .loading(
    apart,
    root: other,
    variables: loadEnvironment(temp).variables,
    manifests: [manifest],
    pause: .clone,
  );
  await load.told(.paused);
  runner.commands.clear();
  final Future<Object> acted = switch (act) {
    .make => muster.scratch(app.name),
    .move => scratch!.move(later),
    .dispose => scratch!.dispose(),
  };
  await waiting.future;
  expect(runner.given, isEmpty, reason: at);
  await load.tell(.go);
  expect(await acted, switch (act) {
    .make => isA<Scratched>(),
    .move => isA<Moved>(),
    .dispose => isA<Disposed>(),
  }, reason: at);
  expect(await load.done(), {
    'app': (
      outcome: OutcomeCase.fetched,
      path: p.join(other, '.dart_tool', 'muster', 'app'),
    ),
  }, reason: at);
  await load.end();
});

/// Matches a scratch that failed for a failure [failure] matches.
Matcher _failedWith(Matcher failure) => isA<ScratchFailed>().having(
  (ScratchFailed s) => s.failure,
  'failure',
  failure,
);

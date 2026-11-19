import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/cli/cli.dart';
import 'package:muster/src/cli/exit_code.dart';
import 'package:muster/src/cli/verb.dart';
import 'package:muster/src/load/loads.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/lock_outcome.dart';
import 'package:muster/src/model/lock_removal.dart';
import 'package:muster/src/model/package_path.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixed_loads.dart';
import '../support/git.dart';
import '../support/host.dart';
import '../support/lines_of.dart';
import '../support/loads.dart';
import '../support/locks.dart';
import '../support/manifests.dart';
import '../support/origin.dart';
import '../support/outcome_case.dart';
import '../support/packages.dart';

/// What a run of the command line gave: the [code] it exits with, and what
/// it wrote to [out] and [err].
typedef _Run = ({ExitCode code, String out, String err});

Future<_Run> _run(Loads loads, List<String> arguments) async {
  final StringBuffer out = .new();
  final StringBuffer err = .new();
  final ExitCode code = await Cli(loads, out, err).run(arguments);
  return (code: code, out: '$out', err: '$err');
}

/// An outcome of [kind] for [codebase], as a command that exited 1 writing
/// `out` leaves it, its kept lock the root's and its executable git.
FetchOutcome _outcome(OutcomeCase kind, GitCodebase codebase) => kind.outcome(
  codebase,
  exitCode: 1,
  output: 'out',
  package: .root,
  executable: .git,
);

/// The rows [out] holds under its header, each split into its cells.
List<List<String>> _rows(String out) {
  final List<List<String>> lines = linesOf(out);
  expect(lines.first, ['name', 'outcome', 'detail']);
  return lines.sublist(1);
}

void main() {
  group('on codebases of git, ', () {
    late Directory temp;
    late Origin origin;

    setUp(() async {
      temp = await .systemTemp.createTemp('muster-');
      origin = await .make(temp, .new(hermetic(temp), host));
    });

    tearDown(() => temp.delete(recursive: true));

    Future<GitCodebase> codebaseNamed(String name, Map<String, String> files) =>
        branchedCodebase(origin, name, files);

    Future<_Run> run(List<String> arguments) =>
        _run(loaderIn(temp, .new(hermetic(temp), host)), arguments);

    test(
      '`muster lock` then `muster fetch` on a manifest of git codebases '
      'that hold no lock of their own exits 0, with every row Fetched',
      () async {
        final GitCodebase app = await codebaseNamed('app', {
          ...packageFiles('app', locked: false),
          ...packageFiles('app_example', at: 'example', locked: false),
        });
        final GitCodebase bench = await codebaseNamed(
          'bench',
          packageFiles('bench', locked: false),
        );
        await writeManifest(atRoot(temp), [app, bench]);
        final _Run locked = await run(['lock']);
        expect(locked.code, ExitCode.done);
        expect(_rows(locked.out), [
          ['app', 'Wrote', keptOf(atRoot(temp), app).path],
          ['app', 'Wrote', keptOf(atRoot(temp), app, .example).path],
          ['bench', 'Wrote', keptOf(atRoot(temp), bench).path],
        ]);
        final _Run fetched = await run(['fetch']);
        expect(fetched.code, ExitCode.done);
        expect(_rows(fetched.out), [
          ['app', 'Fetched', checkoutAt(temp, 'app')],
          ['bench', 'Fetched', checkoutAt(temp, 'bench')],
        ]);
        expect(fetched.err, isEmpty);
      },
    );

    test('`muster fetch` before `muster lock` exits 1 on the codebase '
        'Unlocked, naming the kept lock it needs', () async {
      final GitCodebase app = await codebaseNamed(
        'app',
        packageFiles('app', locked: false),
      );
      await writeManifest(atRoot(temp), [app]);
      final _Run fetched = await run(['fetch']);
      expect(fetched.code.code, 1);
      expect(_rows(fetched.out), [
        ['app', 'Unlocked', keptOf(atRoot(temp), app).path],
      ]);
    });

    test("a command that fails writes its exit code and output to the error "
        'stream, headed by its codebase', () async {
      await writeManifest(atRoot(temp), [
        codebaseOf(
          await .make(
            await .new(p.join(temp.path, 'other')).create(),
            .new(hermetic(temp), host),
          ),
          await origin.commit(),
        ),
      ]);
      await Directory(p.join(temp.path, 'other', 'origin'))
          .delete(recursive: true);
      final _Run fetched = await run(['fetch']);
      expect(fetched.code, ExitCode.failed);
      expect(_rows(fetched.out).single.take(2), ['app', 'CommandFailed']);
      expect(fetched.err, startsWith('app: git clone '));
      expect(fetched.err, contains(' exited 128\nfatal: '));
    });

    test('`muster fetch` and `muster lock` read the manifests named in place '
        "of the root's", () async {
      final String named = p.join(temp.path, 'named.yaml');
      await writeManifest(named, [
        await codebaseNamed('app', packageFiles('app')),
      ]);
      await writeManifest(atRoot(temp), [
        await codebaseNamed('bench', packageFiles('bench', locked: false)),
      ]);
      expect(_rows((await run(['lock', named])).out), isEmpty);
      expect(_rows((await run(['fetch', named])).out), [
        ['app', 'Fetched', checkoutAt(temp, 'app')],
      ]);
    });

    test('a refused run writes why to the error stream and no rows, and '
        'exits 2', () async {
      for (final Verb verb in Verb.values) {
        final _Run refused = await run([verb.name]);
        expect(refused.code, ExitCode.refused);
        expect(refused.out, isEmpty);
        expect(refused.err, startsWith('no manifest: '));
      }
    });
  });

  group('`muster lock`', () {
    final KeptLockPath written = listedKeptLock(
      locksBeside('/consumer/muster.yaml'),
      'app-1.lock',
    )!;
    final KeptLockPath removed = listedKeptLock(
      locksBeside('/consumer/muster.yaml'),
      'gone-1.lock',
    )!;

    test('prints a row for each lock it writes and removes, a removed '
        "lock's name cell empty, and exits 0", () async {
      final _Run run = await _run(
        FixedLoads(
          locks: Locked(
            {
              .parse('app')!: LocksWritten([written]),
            },
            [LockRemoved(removed)],
          ),
        ),
        ['lock'],
      );
      expect(run.code, ExitCode.done);
      expect(_rows(run.out), [
        ['app', 'Wrote', written.path],
        ['', 'Removed', removed.path],
      ]);
    });

    test('prints a codebase that wrote nothing no row', () async {
      final _Run run = await _run(
        FixedLoads(
          locks: Locked({.parse('app')!: const LocksWritten([])}, const []),
        ),
        ['lock'],
      );
      expect(run.code, ExitCode.done);
      expect(_rows(run.out), isEmpty);
    });

    final GitCodebase app = codebase(
      'app',
      '/srv/app.git',
      'a' * 40,
      '.',
      .dart,
    );
    for (final OutcomeCase kind in OutcomeCase.values) {
      final FetchOutcome outcome = _outcome(kind, app);
      final ActFailure failure;
      switch (outcome) {
        case Fetched() || Unlocked():
          continue;
        case final ActFailure actFailure:
          failure = actFailure;
      }
      test(
        'exits 1 on a codebase whose write fails as '
        '${outcome.runtimeType}, its row the failure as fetch prints it',
        () async {
          final _Run lock = await _run(
            FixedLoads(
              locks: Locked({app.name: LockFailed(failure)}, const []),
            ),
            ['lock'],
          );
          final _Run fetch = await _run(
            FixedLoads.loading({app.name: outcome}),
            ['fetch'],
          );
          expect(lock.code.code, 1);
          expect(_rows(lock.out), _rows(fetch.out));
          expect(lock.err, fetch.err);
        },
      );
    }

    test('exits 1 on a removal that fails, its row the path and its reason '
        'on the error stream', () async {
      final _Run run = await _run(
        FixedLoads(
          locks: const Locked({}, [
            RemovalFailed(.new('/locks/gone.lock', 'Permission denied')),
          ]),
        ),
        ['lock'],
      );
      expect(run.code.code, 1);
      expect(_rows(run.out), [
        ['', 'StoreFailed', '/locks/gone.lock'],
      ]);
      expect(run.err, '/locks/gone.lock: Permission denied\n');
    });

    test("writes each failure's note in its row's order, a codebase's before "
        "a removal's", () async {
      final _Run run = await _run(
        FixedLoads(
          locks: Locked(
            {
              app.name: LockFailed(
                _outcome(.commandFailed, app) as CommandFailed,
              ),
            },
            const [
              RemovalFailed(.new('/locks/gone.lock', 'Permission denied')),
            ],
          ),
        ),
        ['lock'],
      );
      expect(_rows(run.out).map((List<String> row) => row.first), ['app', '']);
      final List<String> notes = run.err.split('\n');
      expect(notes.first, startsWith('app: '));
      expect(notes.sublist(notes.length - 2), [
        '/locks/gone.lock: Permission denied',
        '',
      ]);
    });
  });

  group('the command line', () {
    test("prints a `Fetched` row's detail as the package's path, and the "
        'path dependency that left its example unresolved after it, its path '
        'quoted, exiting 0', () async {
      final PackagePath package = packageIn(
        .of(.new('/consumer', .posix), .parse('app')!),
        .parse('.')!,
        .root,
      );
      final Map<CodebaseName, FetchOutcome> outcomes = {
        .parse('none')!: Fetched(package, const NoExample(), .parse('3.13.0')!),
        .parse('resolved')!: Fetched(
          package,
          ExampleResolved(
            packageIn(
              .of(.new('/consumer', .posix), .parse('app')!),
              .parse('.')!,
              .example,
            ),
          ),
          .parse('3.13.0')!,
        ),
        .parse('unresolved')!: Fetched(
          package,
          ExampleUnresolved((
            dependency: .parse('freezed_annotation')!,
            path: '../../freezed\tannotation\n',
          )),
          .parse('3.13.0')!,
        ),
      };
      final _Run run = await _run(FixedLoads.loading(outcomes), ['fetch']);
      expect(run.code, ExitCode.done);
      expect(run.err, isEmpty);
      expect(_rows(run.out), [
        ['none', 'Fetched', '/consumer/.dart_tool/muster/app'],
        ['resolved', 'Fetched', '/consumer/.dart_tool/muster/app'],
        [
          'unresolved',
          'Fetched',
          '/consumer/.dart_tool/muster/app (example unresolved: '
              'freezed_annotation at "../../freezed\\tannotation\\n")',
        ],
      ]);
    });

    test(
      "quotes a row's detail holding a tab or a line break, or opening "
      'on a quote, with each escaped, and leaves every other standing',
      () async {
        final GitCodebase tabbed = codebase(
          'tabbed',
          '/srv/a\tb.git',
          'a' * 40,
          'a\tb',
          .dart,
        );
        final PackagePath rooted = packageIn(
          .of(.new('/consumer', .posix), tabbed.name),
          tabbed.root,
          .root,
        );
        final _Run fetch = await _run(
          FixedLoads.loading({
            tabbed.name: _outcome(.commandFailed, tabbed),
            .parse('broken')!: const StoreFailed('/con\nsumer/app', 'gone'),
            .parse('quoted')!: const StoreFailed('"app', 'gone'),
            .parse('plain')!: const StoreFailed('/consumer/a b"c', 'gone'),
            .parse('rooted')!: Fetched(
              rooted,
              const NoExample(),
              .parse('3.13.0')!,
            ),
            .parse('unresolved')!: Fetched(
              rooted,
              ExampleUnresolved((dependency: .parse('x')!, path: '../y')),
              .parse('3.13.0')!,
            ),
          }),
          ['fetch'],
        );
        expect(_rows(fetch.out), [
          ['tabbed', 'CommandFailed', r'"git clone /srv/a\tb.git"'],
          ['broken', 'StoreFailed', r'"/con\nsumer/app"'],
          ['quoted', 'StoreFailed', r'"\"app"'],
          ['plain', 'StoreFailed', '/consumer/a b"c'],
          ['rooted', 'Fetched', r'"/consumer/.dart_tool/muster/tabbed/a\tb"'],
          [
            'unresolved',
            'Fetched',
            r'"/consumer/.dart_tool/muster/tabbed/a\tb (example unresolved: '
                r'x at \"../y\")"',
          ],
        ]);
        final _Run lock = await _run(
          FixedLoads(
            locks: Locked(
              {
                tabbed.name: LocksWritten([
                  listedKeptLock(
                    locksBeside('/con\tsumer/muster.yaml'),
                    'a.lock',
                  )!,
                ]),
              },
              [
                LockRemoved(
                  listedKeptLock(
                    locksBeside('/consumer/muster.yaml'),
                    'go\u2028ne.lock',
                  )!,
                ),
              ],
            ),
          ),
          ['lock'],
        );
        expect(_rows(lock.out), [
          ['tabbed', 'Wrote', r'"/con\tsumer/muster_locks/a.lock"'],
          ['', 'Removed', r'"/consumer/muster_locks/go\u2028ne.lock"'],
        ]);
      },
    );

    test('passes the manifests named on to the run, and none where none '
        'is', () async {
      final FixedLoads loads = .new();
      await _run(loads, ['fetch', 'a.yaml', 'b.yaml']);
      await _run(loads, ['lock', '--', '-c.yaml']);
      await _run(loads, ['fetch']);
      expect(loads.named, [
        ['a.yaml', 'b.yaml'],
        ['-c.yaml'],
        <String>[],
      ]);
    });

    for (final List<String> arguments in [
      ['--help'],
      ['-h'],
      ['fetch', '--help'],
      ['lock', '-h'],
    ]) {
      test('prints its usage for ${arguments.join(' ')} and exits 0, running '
          'nothing', () async {
        final FixedLoads loads = .new();
        final _Run run = await _run(loads, arguments);
        expect(run.code, ExitCode.done);
        expect(run.out, startsWith('Usage: muster <command> [manifest...]\n'));
        expect(run.err, isEmpty);
        expect(loads.named, isEmpty);
      });
    }

    for (final (List<String> arguments, String said) in [
      (<String>[], ''),
      (['nope'], 'no command named nope\n\n'),
      (['--nope'], 'Could not find an option named "--nope".\n\n'),
      (['fetch', '--nope'], 'Could not find an option named "--nope".\n\n'),
    ]) {
      test('exits 64 on `${arguments.join(' ')}`, saying why beside its '
          'usage, and runs nothing', () async {
        final FixedLoads loads = .new();
        final _Run run = await _run(loads, arguments);
        expect(run.code, ExitCode.usage);
        expect(run.out, isEmpty);
        expect(run.err, startsWith('${said}Usage: muster '));
        expect(loads.named, isEmpty);
      });
    }

    test('names every command in its usage', () async {
      final _Run run = await _run(FixedLoads(), ['-h']);
      expect(run.out, contains('\n  fetch  '));
      expect(run.out, contains('\n  lock   '));
    });
  });
}

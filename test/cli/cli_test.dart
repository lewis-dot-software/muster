import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/cli/cli.dart';
import 'package:muster/src/cli/exit_code.dart';
import 'package:muster/src/cli/verb.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/load/loads.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/lock_outcome.dart';
import 'package:muster/src/model/lock_removal.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixed_loads.dart';
import '../support/git.dart';
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
  final List<String> lines = out.split('\n');
  expect(lines.first, 'name\toutcome\tdetail');
  expect(lines.last, isEmpty);
  return [
    for (final String line in lines.sublist(1, lines.length - 1))
      line.split('\t'),
  ];
}

void main() {
  group('on codebases of git, ', () {
    late Directory temp;
    late Origin origin;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('muster-');
      origin = await .make(temp, .new(hermetic(temp)));
    });

    tearDown(() => temp.delete(recursive: true));

    Future<GitCodebase> codebaseNamed(
      String name,
      Map<String, String> files,
    ) async {
      final Commit pin = await origin.commit(null, files);
      await origin.ref('refs/heads/$name', pin);
      return codebaseOf(origin, pin, name: name);
    }

    Future<_Run> run(List<String> arguments) =>
        _run(loaderIn(temp, .new(hermetic(temp))), arguments);

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
          await Origin.make(
            await Directory(p.join(temp.path, 'other')).create(),
            .new(hermetic(temp)),
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
    final KeptLockPath written = .listed(
      locksBeside('/consumer/muster.yaml'),
      'app-1.lock',
    )!;
    final KeptLockPath removed = .listed(
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
            RemovalFailed(StoreFailed('/locks/gone.lock', 'Permission denied')),
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
              RemovalFailed(
                StoreFailed('/locks/gone.lock', 'Permission denied'),
              ),
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

import 'dart:async';
import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/model/claim_path.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/store/claims.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/chmod.dart';
import '../support/git.dart';
import '../support/loads.dart';
import '../support/locker.dart';
import '../support/locks.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/probe_gone.dart';
import '../support/refusal_case.dart';
import '../support/skipped_unless_modes_deny.dart';
import '../support/spy_runner.dart';
import '../support/waiting_into.dart';
import '../support/write_file.dart';

void main() {
  late Directory temp;
  late SpyRunner runner;
  late Origin origin;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    runner = .new(hermetic(temp));
    origin = await .make(temp, runner);
  });

  tearDown(() => temp.delete(recursive: true));

  /// A codebase [name] of the origin, at a new commit on its own branch
  /// holding [files], the package `app` with no lock where none is given,
  /// its root at [root].
  Future<GitCodebase> codebaseNamed(
    String name, {
    Map<String, String>? files,
    String root = '.',
  }) => branchedCodebase(
    origin,
    name,
    files ?? packageFiles('app', locked: false),
    root: root,
  );

  Future<Locking> lock({List<String> named = const [], Runner? by}) =>
      loaderIn(temp, by ?? runner).lock(named: named);

  Future<Load> load() => loaderIn(temp, runner).load();

  test("a lock writes each kept lock a codebase lacks, its root's and its "
      "example's, each from a resolve afresh, and the load after it fetches "
      'the codebase on them', () async {
    final GitCodebase app = await codebaseNamed(
      'app',
      files: {
        ...packageFiles('app', at: 'pkg', locked: false),
        ...packageFiles('app_example', at: 'pkg/example', locked: false),
      },
      root: 'pkg',
    );
    await writeManifest(atRoot(temp), [app]);
    final List<KeptLockPath> kept = [
      keptOf(atRoot(temp), app),
      keptOf(atRoot(temp), app, .example),
    ];
    expect(await lock(), lockedWith({'app': wrote(kept)}));
    for (final KeptLockPath lock in kept) {
      expect(await File(lock.path).readAsString(), endsWith(lockText));
    }
    expect(
      await load(),
      loadedWith({'app': fetchedAt(p.join(checkoutAt(temp, 'app'), 'pkg'))}),
    );
  });

  test('a lock leaves a kept lock that is there untouched, and writes the '
      'one lacking beside it', () async {
    final GitCodebase app = await codebaseNamed(
      'app',
      files: {
        ...packageFiles('app', locked: false),
        ...packageFiles('app_example', at: 'example', locked: false),
      },
    );
    await writeManifest(atRoot(temp), [app]);
    const String standing = '# kept by hand\n$lockText';
    await writeFile(keptOf(atRoot(temp), app).path, standing);
    expect(
      await lock(),
      lockedWith({
        'app': wrote([keptOf(atRoot(temp), app, .example)]),
      }),
    );
    expect(await File(keptOf(atRoot(temp), app).path).readAsString(), standing);
  });

  test('a codebase whose commit holds its every lock needs no kept lock, '
      'and its checkout is left untouched', () async {
    final GitCodebase app = await codebaseNamed(
      'app',
      files: packageFiles('app'),
    );
    await writeManifest(atRoot(temp), [app]);
    expect(await lock(), lockedWith({'app': wrote(const [])}));
    expect(await Directory(locksBeside(atRoot(temp)).path).exists(), isFalse);
    expect(await Directory(checkoutAt(temp, 'app')).exists(), isFalse);
  });

  test('a kept lock is written to its partial and moved into place, so a '
      'write that fails leaves no kept lock', () async {
    final GitCodebase app = await codebaseNamed('app');
    await writeManifest(atRoot(temp), [app]);
    final String partial = '${keptOf(atRoot(temp), app).path}.partial';
    await Directory(partial).create(recursive: true);
    expect(
      await lock(),
      lockedWith({
        'app': lockFailed(
          isA<StoreFailed>().having((StoreFailed f) => f.path, 'path', partial),
        ),
      }),
    );
    expect(await File(keptOf(atRoot(temp), app).path).exists(), isFalse);
    await Directory(partial).delete();
    expect(
      await lock(),
      lockedWith({
        'app': wrote([keptOf(atRoot(temp), app)]),
      }),
    );
    expect(await File(partial).exists(), isFalse);
  });

  test('a lock that writes a kept lock deletes the stamp of the checkout it '
      'resolves in, so the next load makes it again', () async {
    final GitCodebase app = await codebaseNamed('app');
    await writeManifest(atRoot(temp), [app]);
    await writeFile(keptOf(atRoot(temp), app).path, lockText);
    expect(await load(), loadedWith({'app': isA<Fetched>()}));
    final String stamp = '${checkoutAt(temp, 'app')}.stamp';
    expect(await File(stamp).exists(), isTrue);
    await File(keptOf(atRoot(temp), app).path).delete();
    expect(
      await lock(),
      lockedWith({
        'app': wrote([keptOf(atRoot(temp), app)]),
      }),
    );
    expect(await File(stamp).exists(), isFalse);
    runner.commands.clear();
    expect(await load(), loadedWith({'app': isA<Fetched>()}));
    expect(runner.given, contains(contains(' --enforce-lockfile ')));
  });

  test('a lock removes from each manifest\'s locks every kept lock and '
      'partial no codebase of that manifest names, and leaves every other '
      'file', () async {
    final GitCodebase app = await codebaseNamed('app');
    final GitCodebase bench = await codebaseNamed('bench');
    final String listed = p.join(temp.path, 'elsewhere', 'listed.yaml');
    await writeManifest(atRoot(temp), [app]);
    await writeManifest(listed, [bench]);
    final String locks = locksBeside(atRoot(temp)).path;
    final String gone = p.join(locks, 'gone-0123.lock');
    final String strayOfBench = keptOf(atRoot(temp), bench).path;
    final String cutShort = p.join(locks, 'gone-0123.example.lock.partial');
    final String ownPartial = '${keptOf(atRoot(temp), app).path}.partial';
    for (final String file in [gone, strayOfBench, cutShort, ownPartial]) {
      await writeFile(file, 'left\n');
    }
    await writeFile(p.join(locks, 'README.md'), 'mine\n');
    await writeFile(p.join(locks, '.lock'), 'mine\n');
    expect(
      await loaderIn(
        temp,
        runner,
        variables: {'MUSTER_MANIFESTS': listed},
      ).lock(),
      lockedWith(
        {
          'app': wrote([keptOf(atRoot(temp), app)]),
          'bench': wrote([keptOf(listed, bench)]),
        },
        removals: [removedLock(strayOfBench), removedLock(gone)],
      ),
    );
    expect(
      [
        await for (final FileSystemEntity entity in Directory(locks).list())
          p.basename(entity.path),
      ]..sort(),
      ['.lock', 'README.md', p.basename(keptOf(atRoot(temp), app).path)],
    );
  });

  test('a removal that fails is a removal of its own, and the lock goes on '
      'to the next', () async {
    if (await skippedUnlessModesDeny(temp)) {
      return;
    }
    final GitCodebase app = await codebaseNamed(
      'app',
      files: packageFiles('app'),
    );
    await writeManifest(atRoot(temp), [app]);
    final Directory locks = .new(locksBeside(atRoot(temp)).path);
    final List<String> gone = [
      for (final String name in ['gone-0123.lock', 'gone-4567.lock'])
        p.join(locks.path, name),
    ];
    for (final String stray in gone) {
      await writeFile(stray, 'left\n');
    }
    await chmod('555', locks);
    addTearDown(() => chmod('755', locks));
    expect(
      await lock(),
      lockedWith(
        {'app': wrote(const [])},
        removals: [
          for (final String stray in gone)
            removalFailed(
              isA<StoreFailed>().having(
                (StoreFailed f) => f.path,
                'path',
                stray,
              ),
            ),
        ],
      ),
    );
  });

  test("a lock's removals come in its locks' file names' order, a partial's "
      'failure among them', () async {
    if (await skippedUnlessModesDeny(temp)) {
      return;
    }
    final GitCodebase app = await codebaseNamed(
      'app',
      files: packageFiles('app'),
    );
    await writeManifest(atRoot(temp), [app]);
    final Directory locks = .new(locksBeside(atRoot(temp)).path);
    final List<String> unnamed = [
      for (final String name in [
        'a-0123.lock.partial',
        'b-0123.lock',
        'c-0123.lock.partial',
      ])
        p.join(locks.path, name),
    ];
    for (final String stray in unnamed) {
      await writeFile(stray, 'left\n');
    }
    await chmod('555', locks);
    addTearDown(() => chmod('755', locks));
    expect(
      await lock(),
      lockedWith(
        {'app': wrote(const [])},
        removals: [
          for (final String stray in unnamed)
            removalFailed(
              isA<StoreFailed>().having(
                (StoreFailed f) => f.path,
                'path',
                stray,
              ),
            ),
        ],
      ),
    );
  });

  group('a codebase whose write fails gets its failure as its outcome, and '
      'the lock goes on to the next,', () {
    Future<void> failsAs(GitCodebase failing, Matcher failure) async {
      final GitCodebase next = await codebaseNamed('next');
      await writeManifest(atRoot(temp), [failing, next]);
      expect(
        await lock(),
        lockedWith({
          failing.name.name: lockFailed(failure),
          'next': wrote([keptOf(atRoot(temp), next)]),
        }),
      );
    }

    test('a pin its URL does not hold, as PinMissing', () async {
      final GitCodebase app = await codebaseNamed('app');
      await failsAs(
        codebaseOf(origin, await origin.commit(), name: 'app'),
        isA<PinMissing>().having((PinMissing m) => m.url, 'url', app.url),
      );
    });

    test('a package whose resolve fails, as CommandFailed', () async {
      await failsAs(
        await codebaseNamed('app', files: {'pubspec.yaml': 'name: [\n'}),
        isA<CommandFailed>().having(
          (CommandFailed f) => f.command.arguments.take(2),
          'command',
          ['pub', 'get'],
        ),
      );
    });

    test('a kept lock that cannot be read, as StoreFailed', () async {
      final GitCodebase app = await codebaseNamed('app');
      await Directory(keptOf(atRoot(temp), app).path).create(recursive: true);
      await failsAs(
        app,
        isA<StoreFailed>().having(
          (StoreFailed f) => f.path,
          'path',
          keptOf(atRoot(temp), app).path,
        ),
      );
    });
  });

  test('a git that cannot start fails as Unstartable', () async {
    await writeManifest(atRoot(temp), [await codebaseNamed('app')]);
    expect(
      await lock(by: unstartableIn(temp)),
      lockedWith({
        'app': lockFailed(
          isA<Unstartable>().having(
            (Unstartable u) => u.executable,
            'executable',
            Executable.git,
          ),
        ),
      }),
    );
  });

  group('a lock refuses as a load does, starting no process and writing no '
      'file,', () {
    test('on a manifest named that is not there', () async {
      final String missing = p.join(temp.path, 'missing.yaml');
      runner.commands.clear();
      expect(
        await lock(named: [missing]),
        isA<LockRefused>().having(
          (LockRefused r) => r.reason,
          'reason',
          isA<ManifestMissing>(),
        ),
      );
      expect(runner.given, isEmpty);
    });

    test('with no cache to clone into', () async {
      await writeManifest(atRoot(temp), [await codebaseNamed('app')]);
      runner.commands.clear();
      expect(
        await loaderIn(temp, runner, cached: false).lock(),
        isA<LockRefused>().having(
          (LockRefused r) => r.reason,
          'reason',
          isA<NoCache>(),
        ),
      );
      expect(runner.given, isEmpty);
      expect(await Directory(locksBeside(atRoot(temp)).path).exists(), isFalse);
    });
  });

  for (final (String held, ClaimPath Function(GitCodebase) claimOf) in [
    (
      "a checkout's",
      (GitCodebase codebase) =>
          .ofCheckout(.of(consumerIn(temp), codebase.name)),
    ),
    ("a clone's", (GitCodebase codebase) => cloneOf(temp, codebase).claim),
  ]) {
    test('a lock waits on $held claim another hold has, running nothing, '
        'then writes once it is let go', () async {
      final GitCodebase app = await codebaseNamed('app');
      await writeManifest(atRoot(temp), [app]);
      runner.commands.clear();
      final Completer<void> waited = .new();
      late Future<Locking> locking;
      await Claims(testLocker).holding(claimOf(app), () async {
        locking = loaderIn(temp, runner, claims: waitingInto(waited)).lock();
        await waited.future;
        expect(runner.given, isEmpty);
      });
      expect(
        await locking,
        lockedWith({
          'app': wrote([keptOf(atRoot(temp), app)]),
        }),
      );
    });
  }

  test('a lock of the process refuses where the working directory is gone, '
      'throwing nothing', () async {
    final String manifest = p.join(temp.path, 'empty.yaml');
    await writeManifest(manifest, []);
    final ProcessResult ran = await probeGone(temp, .lock, manifest);
    expect(
      ran.stdout,
      RefusalCase.noWorkingDirectory.name,
      reason: '${ran.stderr}',
    );
  });
}

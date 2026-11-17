import 'dart:io';

import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/example.dart';
import 'package:muster/src/model/checkout.dart';
import 'package:muster/src/model/command.dart';
import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/fetch_outcome.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/lock_source.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/package_path.dart';
import 'package:muster/src/model/parse_stamp.dart';
import 'package:muster/src/model/sdk_version.dart';
import 'package:muster/src/model/stamp.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:muster/src/store/checkouts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/faults.dart';
import '../support/git.dart';
import '../support/loads.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/scratches.dart';
import '../support/spy_runner.dart';
import '../support/write_file.dart';

/// What a resolve found of a package as it began: whether its lock was
/// [locked] in place, and whether a `package_config.json` showed it already
/// [resolved].
typedef _Found = ({bool locked, bool resolved});

void main() {
  late Directory temp;
  late SpyRunner runner;
  late Origin origin;
  late Checkouts checkouts;
  late LocksDirectory locks;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    runner = .new(hermetic(temp));
    origin = await .make(temp, runner);
    checkouts = checkoutsIn(temp, runner);
    locks = locksBeside(atRoot(temp));
  });

  tearDown(() => temp.delete(recursive: true));

  /// A commit on `main` holding [files], at its tip.
  Future<Commit> onMain(Map<String, String> files, [Commit? parent]) async {
    final Commit commit = await origin.commit(parent, files);
    await origin.ref('refs/heads/main', commit);
    return commit;
  }

  /// The path of [file] in the checkout, given relative to its top in `/`
  /// separators.
  String inCheckout(String file) => fileIn(appCheckout(checkouts), file);

  /// The repo the checkout's worktree belongs to, its links resolved.
  Future<String> commonDir() async => Directory(
    (await runner.run((
      executable: .git,
      arguments: [
        '-C',
        appCheckout(checkouts).path,
        'rev-parse',
        '--path-format=absolute',
        '--git-common-dir',
      ],
    ))).stdout.trim(),
  ).resolveSymbolicLinks();

  /// The clone of [codebase]'s URL in the cache, its links resolved.
  Future<String> resolvedClone(GitCodebase codebase) =>
      Directory(cloneOf(temp, codebase).path).resolveSymbolicLinks();

  /// The commit the checkout's `HEAD` stands at.
  Future<String> head() => headOf(appCheckout(checkouts).path, runner);

  /// The version of the Dart SDK on `PATH`.
  Future<SdkVersion> dartVersion() async =>
      readSdkVersion(.dart, (await runner.run(Toolchain.dart.version)).stdout)!;

  /// Whether a command given since the last clear made the checkout again.
  bool madeAgain() => runner.given.any(
    (String command) =>
        command.contains(' worktree add ') || command.contains(' checkout '),
  );

  /// The checkout of [codebase], then each command cleared, so the next call
  /// is the one watched.
  Future<Checkout> warm(GitCodebase codebase) async {
    final Checkout checkout = await checkouts.checkout(Git(codebase), locks);
    runner.commands.clear();
    return checkout;
  }

  /// The stamp beside the checkout.
  Future<Stamp?> stamp() async =>
      parseStamp(await File(appCheckout(checkouts).stamp.path).readAsString());

  test('a checkout comes back at its pin, resolved, handed out at its root, '
      'with the SDK that resolved it', () async {
    final Commit pin = await onMain(packageFiles('app'));
    final Checkout checkout = await checkouts.checkout(
      Git(codebaseOf(origin, pin)),
      locks,
    );
    expect(checkout.package.path, appCheckout(checkouts).path);
    expect(checkout.sdk, await dartVersion());
    expect(await head(), pin.hash);
    expect(await commonDir(), await resolvedClone(codebaseOf(origin, pin)));
    expect(await File(checkout.package.packageConfig.path).exists(), isTrue);
    expect((await stamp())?.codebase, Git(codebaseOf(origin, pin)));
  });

  test('a checkout that stands comes back with nothing run but the '
      'survey', () async {
    final GitCodebase codebase = codebaseOf(
      origin,
      await onMain(packageFiles('app')),
    );
    final Checkout first = await warm(codebase);
    // A new load's, since a load reads each SDK version once.
    final Checkout second = await checkoutsIn(
      temp,
      runner,
    ).checkout(Git(codebase), locks);
    expect(second, first);
    expect(runner.given, [
      'dart --version',
      'git -C ${appCheckout(checkouts).path} --git-dir=.git --work-tree=. '
          '--no-optional-locks status --porcelain=v2 --branch -z '
          '--untracked-files=no',
    ]);
  });

  group('each package resolves on its lock:', () {
    test(
      'a root inside the repo is the package resolved and handed out',
      () async {
        final Commit pin = await onMain(
          packageFiles('inner', at: 'pkgs/inner'),
        );
        final Checkout checkout = await checkouts.checkout(
          Git(codebaseOf(origin, pin, root: 'pkgs/inner')),
          locks,
        );
        expect(checkout.package.path, inCheckout('pkgs/inner'));
        expect(
          await File(checkout.package.packageConfig.path).exists(),
          isTrue,
        );
      },
    );

    test('an example with a pubspec of its own is resolved beside the root '
        'and handed out resolved, and an example/ with none is not, and is '
        'handed out as none', () async {
      final GitCodebase codebase = codebaseOf(
        origin,
        await onMain({
          ...packageFiles('app'),
          ...packageFiles('app_example', at: 'example'),
        }),
      );
      final Checkout resolved = await checkouts.checkout(Git(codebase), locks);
      expect(
        await File(inCheckout('example/.dart_tool/package_config.json'))
            .exists(),
        isTrue,
      );
      expect((await stamp())?.packages.keys, [Package.root, Package.example]);
      expect(
        resolved.example,
        ExampleResolved(
          packageIn(appCheckout(checkouts), codebase.root, .example),
        ),
      );
      expect(
        (await checkoutsIn(
          temp,
          runner,
        ).checkout(Git(codebase), locks)).example,
        resolved.example,
      );
      final Commit bare = await onMain({
        ...packageFiles('app'),
        'example/main.dart': 'void main() {}\n',
      });
      final Checkout none = await checkouts.checkout(
        Git(codebaseOf(origin, bare)),
        locks,
      );
      expect(
        await Directory(inCheckout('example/.dart_tool')).exists(),
        isFalse,
      );
      expect((await stamp())?.packages.keys, [Package.root]);
      expect(none.example, const NoExample());
    });

    test('a package whose commit holds no lock resolves on its kept lock, '
        'placed in it', () async {
      final GitCodebase codebase = codebaseOf(
        origin,
        await onMain(packageFiles('app', locked: false)),
      );
      final KeptLockPath kept = keptLockOf(locks, Git(codebase), .root);
      final String text = '# kept\n$lockText';
      await writeFile(kept.path, text);
      await checkouts.checkout(Git(codebase), locks);
      expect(await File(inCheckout('pubspec.lock')).readAsString(), text);
      expect(
        await File(inCheckout('.dart_tool/package_config.json')).exists(),
        isTrue,
      );
    });

    test('an example whose commit holds no lock resolves on its kept lock, '
        'beside a root on its own', () async {
      final GitCodebase codebase = codebaseOf(
        origin,
        await onMain({
          ...packageFiles('app'),
          ...packageFiles('app_example', at: 'example', locked: false),
        }),
      );
      final KeptLockPath kept = keptLockOf(locks, Git(codebase), .example);
      final String text = '# kept\n$lockText';
      await writeFile(kept.path, text);
      await checkouts.checkout(Git(codebase), locks);
      expect(
        await File(inCheckout('example/pubspec.lock')).readAsString(),
        text,
      );
      expect(
        await File(inCheckout('example/.dart_tool/package_config.json'))
            .exists(),
        isTrue,
      );
      expect(
        (await stamp())?.packages[Package.example]?.source,
        LockSource.kept,
      );
    });

    test('every kept lock is in place before any package resolves, and each '
        'package resolves alone', () async {
      final GitCodebase codebase = codebaseOf(
        origin,
        await onMain({
          ...packageFiles('app'),
          ...packageFiles('app_example', at: 'example', locked: false),
        }),
      );
      final KeptLockPath kept = keptLockOf(locks, Git(codebase), .example);
      await writeFile(kept.path, lockText);
      final PackagePath example = packageIn(
        appCheckout(checkouts),
        codebase.root,
        .example,
      );
      // What each resolve found of the example as it began, by the
      // directory it resolves.
      final Map<String, _Found> found = {};
      runner.answer = (Command command) {
        if (command.arguments.take(2).join(' ') == 'pub get') {
          found[command.arguments.last] = (
            locked: File(example.lock.path).existsSync(),
            resolved: File(example.packageConfig.path).existsSync(),
          );
        }
        return null;
      };
      await checkouts.checkout(Git(codebase), locks);
      expect(found, {
        '--directory=${appCheckout(checkouts).path}': (
          locked: true,
          resolved: false,
        ),
        '--directory=${example.path}': (locked: true, resolved: false),
      });
    });

    test('a lock its commit holds wins over a kept lock', () async {
      final GitCodebase codebase = codebaseOf(
        origin,
        await onMain(packageFiles('app')),
      );
      final KeptLockPath kept = keptLockOf(locks, Git(codebase), .root);
      await writeFile(kept.path, '# kept\n$lockText');
      await checkouts.checkout(Git(codebase), locks);
      expect(await File(inCheckout('pubspec.lock')).readAsString(), lockText);
    });

    test('a package with neither lock fails as Unlocked, naming the kept lock '
        'it needs, and leaves the checkout as it stood', () async {
      final GitCodebase locked = codebaseOf(
        origin,
        await onMain(packageFiles('app')),
      );
      await checkouts.checkout(Git(locked), locks);
      final GitCodebase unlocked = codebaseOf(
        origin,
        await onMain({
          ...packageFiles('app'),
          ...packageFiles('app_example', at: 'example', locked: false),
        }),
      );
      runner.commands.clear();
      await expectLater(
        checkouts.checkout(Git(unlocked), locks),
        throwsA(
          storeFault(
            isA<Unlocked>().having(
              (Unlocked u) => u.lock,
              'lock',
              keptLockOf(locks, Git(unlocked), .example),
            ),
          ),
        ),
      );
      expect(madeAgain(), isFalse);
      expect(await head(), locked.commit.hash);
      expect((await stamp())?.codebase, Git(locked));
    });

    test('a root with neither lock fails as Unlocked, naming the root\'s kept '
        'lock', () async {
      final GitCodebase unlocked = codebaseOf(
        origin,
        await onMain({
          ...packageFiles('app', locked: false),
          ...packageFiles('app_example', at: 'example'),
        }),
      );
      await expectLater(
        checkouts.checkout(Git(unlocked), locks),
        throwsA(
          storeFault(
            isA<Unlocked>().having(
              (Unlocked u) => u.lock,
              'lock',
              keptLockOf(locks, Git(unlocked), .root),
            ),
          ),
        ),
      );
    });
  });

  group('a checkout is made again at its pin where', () {
    late GitCodebase codebase;

    setUp(() async {
      codebase = codebaseOf(
        origin,
        await onMain({...packageFiles('app'), 'lib/app.dart': 'int a = 1;\n'}),
      );
      await warm(codebase);
    });

    /// That the checkout was made again at the pin, holding its tracked
    /// files as the pin does, and stamped afresh.
    Future<void> remade() async {
      expect(madeAgain(), isTrue);
      expect(await head(), codebase.commit.hash);
      expect(
        await File(inCheckout('lib/app.dart')).readAsString(),
        'int a = 1;\n',
      );
      expect(await stamp(), isNotNull);
      runner.commands.clear();
      await checkouts.checkout(Git(codebase), locks);
      expect(madeAgain(), isFalse);
    }

    test('a tracked file is edited', () async {
      await File(inCheckout('lib/app.dart')).writeAsString('int a = 2;\n');
      await checkouts.checkout(Git(codebase), locks);
      await remade();
    });

    test('a tracked file is deleted', () async {
      await File(inCheckout('lib/app.dart')).delete();
      await checkouts.checkout(Git(codebase), locks);
      await remade();
    });

    test('HEAD is moved off the pin', () async {
      await runner.run((
        executable: .git,
        arguments: [
          '-C',
          appCheckout(checkouts).path,
          'commit',
          '--quiet',
          '--allow-empty',
          '--message=off',
        ],
      ));
      runner.commands.clear();
      await checkouts.checkout(Git(codebase), locks);
      await remade();
    });

    test('a package_config.json is not the one stamped', () async {
      await File(inCheckout('.dart_tool/package_config.json'))
          .writeAsString('{}');
      await checkouts.checkout(Git(codebase), locks);
      await remade();
      expect(
        await File(inCheckout('.dart_tool/package_config.json')).readAsString(),
        isNot('{}'),
      );
    });

    test('the stamp is gone, or holds no stamp', () async {
      await File(appCheckout(checkouts).stamp.path).delete();
      await checkouts.checkout(Git(codebase), locks);
      await remade();
      await File(appCheckout(checkouts).stamp.path)
          .writeAsString('not a stamp');
      runner.commands.clear();
      await checkouts.checkout(Git(codebase), locks);
      await remade();
    });

    test('the SDK version on PATH is not the one stamped', () async {
      runner.answer = (Command command) =>
          command.arguments.join(' ') == '--version'
          ? (
              exitCode: 0,
              stdout: 'Dart SDK version: 9.9.9 (stable)',
              stderr: '',
            )
          : null;
      // A new load's, since a load reads each SDK version once.
      checkouts = checkoutsIn(temp, runner);
      final Checkout checkout = await checkouts.checkout(Git(codebase), locks);
      expect(checkout.sdk, SdkVersion.parse('9.9.9'));
      expect((await stamp())?.sdk, SdkVersion.parse('9.9.9'));
      await remade();
    });

    test('the checkout\'s directory is deleted by hand', () async {
      await Directory(appCheckout(checkouts).path).delete(recursive: true);
      await checkouts.checkout(Git(codebase), locks);
      await remade();
    });

    test('the cache is deleted, its clone with it', () async {
      await Directory(cacheDirectoryIn(temp).path).delete(recursive: true);
      await checkouts.checkout(Git(codebase), locks);
      await remade();
    });

    test('a directory that is no worktree stands where the checkout '
        'goes', () async {
      await Directory(appCheckout(checkouts).path).delete(recursive: true);
      await File(inCheckout('lib/app.dart')).create(recursive: true);
      await File(inCheckout('stray')).writeAsString('stray');
      await checkouts.checkout(Git(codebase), locks);
      await remade();
      expect(await File(inCheckout('stray')).exists(), isFalse);
    });

    test('a link to nothing stands where the checkout goes', () async {
      await Directory(appCheckout(checkouts).path).delete(recursive: true);
      await Link(appCheckout(checkouts).path)
          .create(p.join(temp.path, 'nowhere'));
      await checkouts.checkout(Git(codebase), locks);
      await remade();
    });
  });

  group('a codebase moved:', () {
    test('a codebase pinned afresh is moved to its new pin', () async {
      final Commit first = await onMain(packageFiles('app'));
      await checkouts.checkout(Git(codebaseOf(origin, first)), locks);
      final Commit second = await onMain({
        ...packageFiles('app'),
        'lib/new.dart': '',
      }, first);
      await checkouts.checkout(Git(codebaseOf(origin, second)), locks);
      expect(await head(), second.hash);
      expect(await File(inCheckout('lib/new.dart')).exists(), isTrue);
    });

    test('a URL spelled afresh takes a worktree of its own clone', () async {
      final GitCodebase codebase = codebaseOf(
        origin,
        await onMain(packageFiles('app')),
      );
      await checkouts.checkout(Git(codebase), locks);
      final GitCodebase respelled = (
        name: codebase.name,
        url: .parse('${origin.url.url}/')!,
        commit: codebase.commit,
        root: codebase.root,
        toolchain: codebase.toolchain,
      );
      await checkouts.checkout(Git(respelled), locks);
      expect(await commonDir(), await resolvedClone(respelled));
    });
  });

  test('a checkout is made again on its kept lock where that is not the one '
      'stamped', () async {
    final GitCodebase codebase = codebaseOf(
      origin,
      await onMain(packageFiles('app', locked: false)),
    );
    final KeptLockPath kept = keptLockOf(locks, Git(codebase), .root);
    await writeFile(kept.path, lockText);
    await warm(codebase);
    await File(kept.path).writeAsString('# again\n$lockText');
    await checkouts.checkout(Git(codebase), locks);
    expect(madeAgain(), isTrue);
    expect(
      await File(inCheckout('pubspec.lock')).readAsString(),
      '# again\n$lockText',
    );
  });

  test('a checkout is made again where the kept lock placed in it is '
      'edited', () async {
    final GitCodebase codebase = codebaseOf(
      origin,
      await onMain(packageFiles('app', locked: false)),
    );
    final KeptLockPath kept = keptLockOf(locks, Git(codebase), .root);
    await writeFile(kept.path, lockText);
    await warm(codebase);
    await File(inCheckout('pubspec.lock')).writeAsString('# edited\n$lockText');
    await checkouts.checkout(Git(codebase), locks);
    expect(madeAgain(), isTrue);
    expect(await File(inCheckout('pubspec.lock')).readAsString(), lockText);
  });

  test('a git repo around the consumer is never touched by a make, nor taken '
      'for a stamped checkout whose .git is gone, even where it stands at '
      'the pin', () async {
    final GitCodebase codebase = codebaseOf(
      origin,
      await onMain(packageFiles('app')),
    );
    await warm(codebase);
    Future<String> outer(List<String> arguments) async => (await runner.run((
      executable: .git,
      arguments: ['-C', temp.path, ...arguments],
    ))).stdout.trim();
    await outer(['init', '--quiet']);
    await outer([
      'fetch',
      '--quiet',
      origin.directory.path,
      codebase.commit.hash,
    ]);
    await outer(['checkout', '--quiet', '--detach', codebase.commit.hash]);
    final String mine = p.join(temp.path, 'mine');
    await File(mine).writeAsString('mine');
    await File(inCheckout('.git')).delete();
    runner.commands.clear();
    await checkouts.checkout(Git(codebase), locks);
    expect(madeAgain(), isTrue);
    expect(await commonDir(), await resolvedClone(codebase));
    expect(await head(), codebase.commit.hash);
    expect(await outer(['rev-parse', 'HEAD']), codebase.commit.hash);
    expect(await File(mine).readAsString(), 'mine');
  });

  test('a resolve that fails fails as CommandFailed, carrying the toolchain\'s '
      'command, and leaves no stamp, even one an earlier make wrote, so the '
      'next call makes it again', () async {
    final Commit stamped = await onMain(packageFiles('app'));
    await checkouts.checkout(Git(codebaseOf(origin, stamped)), locks);
    expect(await File(appCheckout(checkouts).stamp.path).exists(), isTrue);
    final GitCodebase codebase = codebaseOf(
      origin,
      await onMain({
        ...packageFiles('app'),
        'pubspec.lock': 'packages: [\n',
      }, stamped),
    );
    await expectLater(
      checkouts.checkout(Git(codebase), locks),
      throwsA(
        storeFault(
          isA<CommandFailed>().having(
            (CommandFailed f) => f.command.arguments.take(2),
            'arguments',
            ['pub', 'get'],
          ),
        ),
      ),
    );
    expect(await File(appCheckout(checkouts).stamp.path).exists(), isFalse);
    runner.commands.clear();
    await expectLater(
      checkouts.checkout(Git(codebase), locks),
      throwsA(storeFault(isA<CommandFailed>())),
    );
    expect(madeAgain(), isTrue);
  });

  test('a version the toolchain writes that names none fails as '
      'CommandFailed', () async {
    runner.answer = (Command command) =>
        command.arguments.join(' ') == '--version'
        ? (exitCode: 0, stdout: 'no version here', stderr: '')
        : null;
    await expectLater(
      checkouts.checkout(
        Git(codebaseOf(origin, await onMain(packageFiles('app')))),
        locks,
      ),
      throwsA(
        storeFault(
          isA<CommandFailed>()
              .having((CommandFailed f) => f.exitCode, 'exitCode', 0)
              .having(
                (CommandFailed f) => f.stdout,
                'stdout',
                'no version here',
              ),
        ),
      ),
    );
  });

  test(
    'a toolchain that cannot start fails as Unstartable, naming it',
    () async {
      final Checkouts unstartable = checkoutsIn(temp, unstartableIn(temp));
      await expectLater(
        unstartable.checkout(
          Git(codebaseOf(origin, await onMain(packageFiles('app')))),
          locks,
        ),
        throwsA(
          storeFault(
            isA<Unstartable>().having(
              (Unstartable u) => u.executable,
              'executable',
              Toolchain.dart.executable,
            ),
          ),
        ),
      );
    },
  );

  test('a consumer root that cannot hold a checkout fails as StoreFailed, '
      'naming the path', () async {
    final GitCodebase codebase = codebaseOf(
      origin,
      await onMain(packageFiles('app')),
    );
    await File(checkouts.root.path).create(recursive: true);
    await expectLater(
      checkouts.checkout(Git(codebase), locks),
      throwsA(
        storeFault(
          isA<StoreFailed>().having(
            (StoreFailed f) => f.path,
            'path',
            startsWith(checkouts.root.path),
          ),
        ),
      ),
    );
  });

  test('a pin its URL does not hold fails as PinMissing', () async {
    await onMain(packageFiles('app'));
    await expectLater(
      checkouts.checkout(Git(codebaseOf(origin, .parse('a' * 40)!)), locks),
      throwsA(storeFault(isA<PinMissing>())),
    );
  });

  test('a Flutter codebase resolves with flutter, and comes back with the '
      'Flutter version on PATH', () async {
    final Commit pin = await onMain(packageFiles('app'));
    final Checkout checkout = await checkouts.checkout(
      Git(codebaseOf(origin, pin, toolchain: .flutter)),
      locks,
    );
    expect(
      checkout.sdk,
      readSdkVersion(
        .flutter,
        (await runner.run(Toolchain.flutter.version)).stdout,
      ),
    );
    expect(
      runner.given,
      contains(startsWith('flutter pub get --enforce-lockfile')),
    );
    expect(await File(checkout.package.packageConfig.path).exists(), isTrue);
  });
}

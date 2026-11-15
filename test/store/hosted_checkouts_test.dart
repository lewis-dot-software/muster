import 'dart:io';

import 'package:muster/src/model/around_pubspec.dart';
import 'package:muster/src/model/checkout.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/example.dart';
import 'package:muster/src/model/executable.dart';
import 'package:muster/src/model/fetch_outcome.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/package_path.dart';
import 'package:muster/src/model/parse_stamp.dart';
import 'package:muster/src/model/sdk_version.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:muster/src/store/checkouts.dart';
import 'package:test/test.dart';

import '../support/faults.dart';
import '../support/git.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
import '../support/spy_runner.dart';

void main() {
  late Directory temp;
  late PackageServer server;
  late SpyRunner runner;
  late Checkouts checkouts;
  late LocksDirectory locks;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    server = await .start();
    runner = .new({...hermetic(temp), ...pubVariables(temp, server)});
    checkouts = checkoutsIn(temp, runner);
    locks = locksBeside(atRoot(temp));
  });

  tearDown(() async {
    await server.close();
    await temp.delete(recursive: true);
  });

  /// The version of [toolchain]'s SDK on `PATH`.
  Future<SdkVersion> versionOf(Toolchain toolchain) async =>
      readSdkVersion(toolchain, (await runner.run(toolchain.version)).stdout)!;

  test('a hosted checkout comes back unpacked at its version, resolved, '
      'handed out at its package, with no example where it serves none and '
      'the SDK that resolved it, and stamped with the codebase', () async {
    serveLeaf(server, 'a', '1.2.3');
    final HostedCodebase codebase = hostedOf('a', version: '1.2.3');
    final Checkout checkout = await lockedCheckout(checkouts, locks, codebase);
    expect(checkout.package.path, '${appCheckout(checkouts).path}/a-1.2.3');
    expect(checkout.example, const NoExample());
    expect(checkout.sdk, await versionOf(.dart));
    expect(await File(checkout.package.packageConfig.path).exists(), isTrue);
    expect(
      parseStamp(await File(appCheckout(checkouts).stamp.path).readAsString())
          ?.codebase,
      Hosted(codebase),
    );
  });

  test('a Flutter codebase resolves with flutter, and comes back with the '
      'Flutter version on PATH', () async {
    serveLeaf(server, 'a', '1.0.0', example: true);
    final Checkout checkout = await lockedCheckout(
      checkouts,
      locks,
      hostedOf('a', resolution: .asDependency, toolchain: .flutter),
    );
    expect(checkout.sdk, await versionOf(.flutter));
    expect(
      runner.given.where((String command) => command.contains(' pub get ')),
      everyElement(startsWith('flutter pub get ')),
    );
    expect(runner.given, contains(startsWith('dart pub unpack a@1.0.0 ')));
  });

  test('a lock writes the kept lock of each package lacking one, in order, '
      'and a lock after it on the checkout made on them writes nothing and '
      'unpacks nothing', () async {
    serveLeaf(server, 'a', '1.0.0', example: true);
    final HostedCodebase codebase = hostedOf('a');
    expect(await checkouts.lock(Hosted(codebase), locks), [
      keptLockOf(locks, Hosted(codebase), .root),
      keptLockOf(locks, Hosted(codebase), .example),
    ]);
    await checkouts.checkout(Hosted(codebase), locks);
    runner.commands.clear();
    expect(await checkouts.lock(Hosted(codebase), locks), isEmpty);
    expect(runner.given, isEmpty);
  });

  test("a lock writes the example's alone where the root's is kept", () async {
    serveLeaf(server, 'a', '1.0.0', example: true);
    final HostedCodebase codebase = hostedOf('a');
    await checkouts.lock(Hosted(codebase), locks);
    await File(keptLockOf(locks, Hosted(codebase), .example).path).delete();
    expect(await checkouts.lock(Hosted(codebase), locks), [
      keptLockOf(locks, Hosted(codebase), .example),
    ]);
  });

  test('a hosted checkout whose unpacked package is gone is unpacked afresh, '
      'never handed out at a path that is not there', () async {
    serveLeaf(server, 'a', '1.0.0');
    final HostedCodebase codebase = hostedOf('a', resolution: .asDependency);
    final Checkout first = await lockedCheckout(checkouts, locks, codebase);
    await Directory(first.package.path).delete(recursive: true);
    runner.commands.clear();
    final Checkout again = await checkoutsIn(
      temp,
      runner,
    ).checkout(Hosted(codebase), locks);
    expect(runner.given, contains(startsWith('dart pub unpack ')));
    expect(await File(again.package.pubspec.path).exists(), isTrue);
  });

  test('a version no host serves fails as CommandFailed, carrying the '
      "unpack's command, and leaves no stamp, even one an earlier make "
      'wrote', () async {
    serveLeaf(server, 'a', '1.0.0');
    await lockedCheckout(checkouts, locks, hostedOf('a'));
    expect(await File(appCheckout(checkouts).stamp.path).exists(), isTrue);
    final HostedCodebase missing = hostedOf('a', version: '2.0.0');
    await expectLater(
      checkouts.checkout(Hosted(missing), locks),
      throwsA(
        storeFault(
          isA<CommandFailed>().having(
            (CommandFailed f) => f.command.arguments.take(2),
            'arguments',
            ['pub', 'unpack'],
          ),
        ),
      ),
    );
    expect(await File(appCheckout(checkouts).stamp.path).exists(), isFalse);
    await expectLater(
      checkouts.lock(Hosted(missing), locks),
      throwsA(storeFault(isA<CommandFailed>())),
    );
  });

  test('a resolve that fails fails as CommandFailed, carrying the '
      "toolchain's command", () async {
    server.serve('a', '1.0.0', {
      'pubspec.yaml': hostedPubspec(
        'a',
        '1.0.0',
        dependencies: {'unserved': '^1.0.0'},
      ),
    });
    await expectLater(
      checkouts.lock(Hosted(hostedOf('a')), locks),
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
  });

  test('a package from a pub workspace resolves alone, and so does its '
      'example where a dependency of the package depends back on it from its '
      'host', () async {
    server.serve('a', '1.0.0', {
      'pubspec.yaml': hostedPubspec(
        'a',
        '1.0.0',
        dependencies: {'c': '^1.0.0'},
        workspace: true,
      ),
      'example/pubspec.yaml': examplePubspec('a', workspace: true),
    });
    server.serve('c', '1.0.0', {
      'pubspec.yaml': hostedPubspec('c', '1.0.0', dependencies: {'a': 'any'}),
    });
    final HostedCodebase codebase = hostedOf('a');
    await lockedCheckout(checkouts, locks, codebase);
    expect(
      await configuredIn(
        hostedPackage(appCheckout(checkouts), codebase, .root),
      ),
      {'a', 'c'},
    );
    expect(
      await configuredIn(
        hostedPackage(appCheckout(checkouts), codebase, .example),
      ),
      {'a', 'a_example', 'c'},
    );
  });

  test('a served example overrides file stands as served', () async {
    const String served = 'dependency_overrides:\n  a:\n    path: ../';
    serveLeaf(
      server,
      'a',
      '1.0.0',
      example: true,
      files: {'example/pubspec_overrides.yaml': served},
    );
    final HostedCodebase codebase = hostedOf('a');
    await lockedCheckout(checkouts, locks, codebase);
    expect(
      await File(
        hostedPackage(
          appCheckout(checkouts),
          codebase,
          .example,
        ).overrides.path,
      ).readAsString(),
      served,
    );
  });

  test('an archive that unpacks with no pubspec fails its resolve as '
      'CommandFailed, never handed out unresolved', () async {
    server.serve('a', '1.0.0', {
      'lib/a.dart': '',
    }, listed: hostedPubspec('a', '1.0.0'));
    final HostedCodebase codebase = hostedOf('a');
    await expectLater(
      checkouts.lock(Hosted(codebase), locks),
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
    await expectLater(
      checkouts.checkout(Hosted(codebase), locks),
      throwsA(storeFault(isA<Unlocked>())),
    );
  });

  test(
    'a lock resolves afresh, never from a lock the package is served',
    () async {
      serveLeaf(server, 'd', '1.0.0');
      serveLeaf(server, 'd', '1.1.0');
      server.serve('a', '1.0.0', {
        'pubspec.yaml': hostedPubspec(
          'a',
          '1.0.0',
          dependencies: {'d': '^1.0.0'},
        ),
        'pubspec.lock': servedLock('d', '1.0.0', server),
      });
      final HostedCodebase codebase = hostedOf('a');
      await checkouts.lock(Hosted(codebase), locks);
      expect(
        await File(keptLockOf(locks, Hosted(codebase), .root).path)
            .readAsString(),
        allOf(contains('version: "1.1.0"'), isNot(contains('"1.0.0"'))),
      );
    },
  );

  test(
    'a toolchain that cannot start fails as Unstartable, naming it',
    () async {
      final Checkouts unstartable = checkoutsIn(temp, unstartableIn(temp));
      await expectLater(
        unstartable.checkout(Hosted(hostedOf('a')), locks),
        throwsA(
          storeFault(
            isA<Unstartable>().having(
              (Unstartable u) => u.executable,
              'executable',
              Executable.dart,
            ),
          ),
        ),
      );
    },
  );

  test('a consumer root that cannot hold a checkout fails as StoreFailed, '
      'naming the path', () async {
    serveLeaf(server, 'a', '1.0.0');
    await File(checkouts.root.path).create(recursive: true);
    await expectLater(
      checkouts.checkout(Hosted(hostedOf('a')), locks),
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

  test('a package resolved as a dependency is handed out itself, beside the '
      'package config and lock of the package around it', () async {
    serveLeaf(server, 'a', '1.0.0');
    final HostedCodebase codebase = hostedOf('a', resolution: .asDependency);
    final Checkout checkout = await lockedCheckout(checkouts, locks, codebase);
    expect(
      await File(checkout.package.pubspec.path).readAsString(),
      hostedPubspec('a', '1.0.0'),
    );
    expect(await configuredIn(checkout.package), {'a', aroundName});
    expect(
      checkout.package.lock.path,
      '${appCheckout(checkouts).path}/pubspec.lock',
    );
  });
}

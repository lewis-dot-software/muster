import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/package.dart';
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/locks.dart';
import '../support/manifests.dart';
import '../support/origin.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
import '../support/spy_runner.dart';
import '../support/write_file.dart';

void main() {
  late Directory temp;
  late PackageServer server;
  late SpyRunner runner;
  late GitCodebase app;
  late HostedCodebase lib;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    server = await .start();
    runner = .new({...hermetic(temp), ...pubVariables(temp, server)});
    final Origin origin = await .make(temp, runner);
    final Commit pin = await origin.commit(null, packageFiles('app'));
    await origin.ref('refs/heads/main', pin);
    app = codebaseOf(origin, pin);
    serveLeaf(server, 'a', '1.0.0', example: true);
    lib = hostedOf('a', name: 'lib');
    await writeFile(
      atRoot(temp),
      renderManifest([entryOf(app), hostedEntryOf(lib)]),
    );
  });

  tearDown(() async {
    await server.close();
    await temp.delete(recursive: true);
  });

  /// The kept lock of the hosted codebase's [package].
  KeptLockPath keptOfLib([Package package = .root]) =>
      .of(locksBeside(atRoot(temp)), Hosted(lib), package);

  test('a manifest naming a git and a hosted codebase locks and loads both, '
      'in its order', () async {
    final Matcher written = lockedWith({
      'app': wrote(const []),
      'lib': wrote([keptOfLib(), keptOfLib(.example)]),
    });
    expect(await loaderIn(temp, runner).lock(), written);
    expect(
      await loaderIn(temp, runner).load(),
      loadedWith({
        'app': fetchedAt(checkoutAt(temp, 'app')),
        'lib': fetchedAt('${checkoutAt(temp, 'lib')}/a-1.0.0'),
      }),
    );
  });

  test('a hosted codebase with no kept lock loads as Unlocked, beside a git '
      'codebase that fetches', () async {
    expect(
      await loaderIn(temp, runner).load(),
      loadedWith({
        'app': isA<Fetched>(),
        'lib': isA<Unlocked>().having(
          (Unlocked u) => u.lock,
          'lock',
          keptOfLib(),
        ),
      }),
    );
  });

  test("a lock removes a hosted codebase's kept locks once no codebase "
      'names it', () async {
    await loaderIn(temp, runner).lock();
    await writeFile(atRoot(temp), renderManifest([entryOf(app)]));
    expect(
      await loaderIn(temp, runner).lock(),
      lockedWith(
        {'app': wrote(const [])},
        // In their file names' order, `.example.lock` before `.lock`.
        removals: [
          removedLock(keptOfLib(.example).path),
          removedLock(keptOfLib().path),
        ],
      ),
    );
  });

  test(
    'a scratch of a hosted codebase is refused as NoClone, naming it',
    () async {
      await loaderIn(temp, runner).lock();
      final Load load = await loaderIn(temp, runner).load();
      final Muster muster = switch (load) {
        Loaded(:final Muster muster) => muster,
        Refused(:final LoadRefusal reason) => fail('refused: $reason'),
      };
      expect(
        await muster.scratch(lib.name),
        isA<NoClone>().having((NoClone n) => n.name, 'name', lib.name),
      );
    },
  );
}

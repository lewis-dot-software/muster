import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
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
  late GitCodebase bare;
  late HostedCodebase lib;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    server = await .start();
    runner = .new({...hermetic(temp), ...pubVariables(temp, server)});
    final Origin origin = await .make(temp, runner);
    final Commit pin = await origin.commit(null, packageFiles('app'));
    await origin.ref('refs/heads/main', pin);
    app = codebaseOf(origin, pin);
    final Commit unlocked = await origin.commit(
      null,
      packageFiles('bare', locked: false),
    );
    await origin.ref('refs/heads/bare', unlocked);
    bare = codebaseOf(origin, unlocked, name: 'bare');
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
      keptLockOf(locksBeside(atRoot(temp)), Hosted(lib), package);

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

  test("each `Fetched` carries its checkout's example: none for a git "
      'codebase that holds none, resolved for a hosted one that resolves, and '
      'left unresolved, naming the path dependency, for one that path-depends '
      'outside its package', () async {
    server.serve('out', '1.0.0', {
      'pubspec.yaml': hostedPubspec('out', '1.0.0'),
      'example/pubspec.yaml':
          '${examplePubspec('out')}  sibling:\n    path: ../../sibling\n',
    });
    final HostedCodebase out = hostedOf('out', name: 'out');
    await writeFile(
      atRoot(temp),
      renderManifest([entryOf(app), hostedEntryOf(lib), hostedEntryOf(out)]),
    );
    await loaderIn(temp, runner).lock();
    Matcher example(Object? matcher) =>
        isA<Fetched>().having((Fetched f) => f.example, 'example', matcher);
    expect(
      await loaderIn(temp, runner).load(),
      loadedWith({
        'app': example(const NoExample()),
        'lib': example(
          isA<ExampleResolved>().having(
            (ExampleResolved e) => e.package.path,
            'package',
            '${checkoutAt(temp, 'lib')}/a-1.0.0/example',
          ),
        ),
        'out': example(
          ExampleUnresolved((
            dependency: .parse('sibling')!,
            path: '../../sibling',
          )),
        ),
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
    'a scratch of a hosted codebase is refused as NotGit, naming it',
    () async {
      await loaderIn(temp, runner).lock();
      final Load load = await loaderIn(temp, runner).load();
      final Muster muster = switch (load) {
        Loaded(:final Muster muster) => muster,
        Refused(:final LoadRefusal reason) => fail('refused: $reason'),
      };
      expect(
        await muster.scratch(lib.name),
        isA<NotGit>().having((NotGit n) => n.name, 'name', lib.name),
      );
    },
  );

  group("a file standing at a checkout's path is removed and the checkout "
      'made afresh where a load or a lock makes it, of a git and a hosted '
      'codebase alike,', () {
    setUp(() async {
      await writeFile(
        atRoot(temp),
        renderManifest([entryOf(app), entryOf(bare), hostedEntryOf(lib)]),
      );
    });

    /// Stands a file at the checkout path of each of [names], in place of
    /// any checkout there.
    Future<void> fileAt(List<String> names) async {
      for (final String name in names) {
        final Directory checkout = .new(checkoutAt(temp, name));
        if (await checkout.exists()) {
          await checkout.delete(recursive: true);
        }
        await writeFile(checkout.path, 'a file\n');
      }
    }

    /// Matches a load that fetched every codebase.
    Matcher fetched() => loadedWith({
      'app': fetchedAt(checkoutAt(temp, 'app')),
      'bare': fetchedAt(checkoutAt(temp, 'bare')),
      'lib': fetchedAt('${checkoutAt(temp, 'lib')}/a-1.0.0'),
    });

    test('by `muster lock`, which leaves the file of a codebase it writes no '
        'lock for, since it makes no checkout of one', () async {
      await fileAt(['app', 'bare', 'lib']);
      expect(
        await loaderIn(temp, runner).lock(),
        lockedWith({
          'app': wrote(const []),
          'bare': wrote([
            keptLockOf(locksBeside(atRoot(temp)), Git(bare), .root),
          ]),
          'lib': wrote([keptOfLib(), keptOfLib(.example)]),
        }),
      );
      for (final String name in ['bare', 'lib']) {
        expect(await Directory(checkoutAt(temp, name)).exists(), isTrue);
      }
      expect(await File(checkoutAt(temp, 'app')).exists(), isTrue);
      expect(await loaderIn(temp, runner).load(), fetched());
    });

    test('by a load', () async {
      await loaderIn(temp, runner).lock();
      await fileAt(['app', 'bare', 'lib']);
      expect(await loaderIn(temp, runner).load(), fetched());
    });
  });
}

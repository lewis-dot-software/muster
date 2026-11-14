import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/load/loader.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/sdk_version.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/loads.dart';
import '../support/locker.dart';
import '../support/manifests.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/probe_gone.dart';
import '../support/spy_runner.dart';
import '../support/write_file.dart';

void main() {
  late Directory temp;
  late SpyRunner runner;
  late Origin origin;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('muster-');
    runner = .new(hermetic(temp));
    origin = await .make(temp, runner);
  });

  tearDown(() => temp.delete(recursive: true));

  /// A codebase [name] of the origin, at a new commit on its own branch
  /// holding [files], the package `app` with its lock where none is given.
  Future<GitCodebase> codebaseNamed(
    String name, [
    Map<String, String>? files,
  ]) async {
    final Commit pin = await origin.commit(null, files ?? packageFiles('app'));
    await origin.ref('refs/heads/$name', pin);
    return codebaseOf(origin, pin, name: name);
  }

  String checkoutOf(String name) => checkoutAt(temp, name);

  Future<Load> load({
    List<String> named = const [],
    String? root,
    Map<String, String> variables = const {},
    Runner? by,
  }) => loaderIn(
    temp,
    by ?? runner,
    variables: variables,
  ).load(named: named, root: root);

  test("a muster.yaml at the root and a manifest MUSTER_MANIFESTS names each "
      'hand out their codebases at their pins, resolved, each on the locks '
      'beside its own manifest', () async {
    final GitCodebase app = await codebaseNamed('app');
    final GitCodebase bench = await codebaseNamed(
      'bench',
      packageFiles('app', locked: false),
    );
    final String second = p.join(temp.path, 'elsewhere', 'bench.yaml');
    await writeManifest(atRoot(temp), [app]);
    await writeManifest(second, [bench]);
    final KeptLockPath kept = keptLockOf(
      locksBeside(second),
      Git(bench),
      .root,
    );
    await writeFile(kept.path, lockText);
    expect(
      await load(variables: {'MUSTER_MANIFESTS': second}),
      loadedWith({
        'app': fetchedAt(checkoutOf('app')),
        'bench': fetchedAt(checkoutOf('bench')),
      }),
    );
    for (final String name in ['app', 'bench']) {
      expect(
        await File(p.join(checkoutOf(name), 'pubspec.yaml')).readAsString(),
        pubspecOf('app'),
      );
      expect(
        await File(
          p.join(checkoutOf(name), '.dart_tool', 'package_config.json'),
        ).exists(),
        isTrue,
      );
    }
  });

  test(
    'a codebase fetched carries the version of the SDK that resolved it',
    () async {
      await writeManifest(atRoot(temp), [await codebaseNamed('app')]);
      expect(
        await load(),
        loadedWith({
          'app': isA<Fetched>().having(
            (Fetched f) => f.sdk,
            'sdk',
            readSdkVersion(
              .dart,
              (await runner.run(Toolchain.dart.version)).stdout,
            ),
          ),
        }),
      );
    },
  );

  test(
    "manifests named replace the root's muster.yaml and MUSTER_MANIFESTS",
    () async {
      final String named = p.join(temp.path, 'named.yaml');
      final String listed = p.join(temp.path, 'listed.yaml');
      await writeManifest(atRoot(temp), [await codebaseNamed('a')]);
      await writeManifest(listed, [await codebaseNamed('b')]);
      await writeManifest(named, [await codebaseNamed('c')]);
      expect(
        await load(named: [named], variables: {'MUSTER_MANIFESTS': listed}),
        loadedWith({'c': fetchedAt(checkoutOf('c'))}),
      );
    },
  );

  test('a manifest named by a relative path is read against the working '
      'directory, and its locks sit beside it', () async {
    final GitCodebase app = await codebaseNamed(
      'app',
      packageFiles('app', locked: false),
    );
    await writeManifest(atRoot(temp, 'sub/bench.yaml'), [app]);
    expect(
      await load(named: ['sub/bench.yaml']),
      loadedWith({
        'app': isA<Unlocked>().having(
          (Unlocked u) => u.lock,
          'lock',
          keptLockOf(
            locksBeside(atRoot(temp, 'sub/bench.yaml')),
            Git(app),
            .root,
          ),
        ),
      }),
    );
  });

  test('a root given by a relative path is read against the working '
      'directory, and the checkouts stand under it', () async {
    final String manifest = p.join(temp.path, 'bench.yaml');
    await writeManifest(manifest, [await codebaseNamed('app')]);
    expect(
      await load(named: [manifest], root: '../other'),
      loadedWith({
        'app': fetchedAt(
          p.join(temp.path, 'other', '.dart_tool', 'muster', 'app'),
        ),
      }),
    );
  });

  test('a manifest with no codebases loads none', () async {
    await writeManifest(atRoot(temp), []);
    expect(await load(), loadedWith({}));
  });

  test('a manifest MUSTER_MANIFESTS names loads with no muster.yaml at the '
      'root', () async {
    final String listed = p.join(temp.path, 'listed.yaml');
    await writeManifest(listed, [await codebaseNamed('app')]);
    expect(
      await load(variables: {'MUSTER_MANIFESTS': listed}),
      loadedWith({'app': fetchedAt(checkoutOf('app'))}),
    );
  });

  group('a codebase that fails gets its failure as its outcome, and the load '
      'goes on to the next:', () {
    Future<void> failsAs(GitCodebase failing, Matcher outcome) async {
      await writeManifest(atRoot(temp), [failing, await codebaseNamed('next')]);
      expect(
        await load(),
        loadedWith({
          failing.name.name: outcome,
          'next': fetchedAt(checkoutOf('next')),
        }),
      );
    }

    test('a pin its URL does not hold, as PinMissing', () async {
      await failsAs(
        codebaseOf(origin, .parse('a' * 40)!),
        isA<PinMissing>().having((PinMissing m) => m.url, 'url', origin.url),
      );
    });

    test('a URL that is no repo, as CommandFailed', () async {
      final GitCodebase app = await codebaseNamed('app');
      await failsAs(
        (
          name: app.name,
          url: .parse(p.join(temp.path, 'no-such-repo'))!,
          commit: app.commit,
          root: app.root,
          toolchain: app.toolchain,
        ),
        isA<CommandFailed>().having(
          (CommandFailed f) => f.command.executable,
          'executable',
          Executable.git,
        ),
      );
    });

    test('a package with no lock, as Unlocked', () async {
      await failsAs(
        await codebaseNamed('app', packageFiles('app', locked: false)),
        isA<Unlocked>(),
      );
    });

    test('a stamp that cannot be read, as StoreFailed', () async {
      await Directory(
        p.join(consumerIn(temp).path, '.dart_tool', 'muster', 'app.stamp'),
      ).create(recursive: true);
      await failsAs(
        await codebaseNamed('app'),
        isA<StoreFailed>().having(
          (StoreFailed f) => f.path,
          'path',
          endsWith('app.stamp'),
        ),
      );
    });
  });

  test('a toolchain that cannot start fails as Unstartable', () async {
    await writeManifest(atRoot(temp), [await codebaseNamed('app')]);
    expect(
      await load(by: unstartableIn(temp)),
      loadedWith({
        'app': isA<Unstartable>().having(
          (Unstartable u) => u.executable,
          'executable',
          Executable.dart,
        ),
      }),
    );
  });

  group('a load refuses, starting no process,', () {
    Future<void> refuses(
      Matcher reason, {
      List<String> named = const [],
      Map<String, String> variables = const {},
    }) async {
      runner.commands.clear();
      expect(
        await load(named: named, variables: variables),
        refusedFor(reason),
      );
      expect(runner.given, isEmpty);
    }

    test('with no manifest at all', () async {
      await refuses(isA<NoManifest>());
    });

    test('with no muster.yaml at the root and nothing but separators in '
        'MUSTER_MANIFESTS', () async {
      await refuses(isA<NoManifest>(), variables: {'MUSTER_MANIFESTS': '::'});
    });

    test(
      'on a manifest whose file name does not end .yaml, naming it',
      () async {
        final String yml = p.join(temp.path, 'muster.yml');
        await writeManifest(yml, []);
        await refuses(
          isA<NotManifestName>().having(
            (NotManifestName n) => n.path,
            'path',
            yml,
          ),
          named: [yml],
        );
      },
    );

    test(
      'on a manifest MUSTER_MANIFESTS names that is missing, naming it',
      () async {
        final String missing = p.join(temp.path, 'missing.yaml');
        await writeManifest(atRoot(temp), []);
        await refuses(
          isA<ManifestMissing>().having(
            (ManifestMissing m) => m.manifest.path,
            'manifest',
            missing,
          ),
          variables: {'MUSTER_MANIFESTS': missing},
        );
      },
    );

    test('on a manifest that cannot be read, naming it and why', () async {
      await Directory(atRoot(temp)).create(recursive: true);
      await refuses(
        isA<ManifestUnreadable>()
            .having(
              (ManifestUnreadable u) => u.manifest.path,
              'manifest',
              atRoot(temp),
            )
            .having((ManifestUnreadable u) => u.reason, 'reason', isNotEmpty),
      );
    });

    test('on a manifest that is not YAML, naming it and why', () async {
      await writeFile(atRoot(temp), 'codebases: [');
      await refuses(
        isA<ManifestInvalid>()
            .having(
              (ManifestInvalid i) => i.manifest.path,
              'manifest',
              atRoot(temp),
            )
            .having(
              (ManifestInvalid i) => i.refusal,
              'refusal',
              isA<NotYaml>().having(
                (NotYaml n) => n.reason,
                'reason',
                isNotEmpty,
              ),
            ),
      );
    });

    test('on a manifest whose bytes are not UTF-8, as not YAML at the byte '
        'it stopped at', () async {
      await File(atRoot(temp)).create(recursive: true);
      await File(atRoot(temp))
          .writeAsBytes([...'codebases: {}\n# '.codeUnits, 0xff, 0xfe]);
      await refuses(
        isA<ManifestInvalid>().having(
          (ManifestInvalid i) => i.refusal,
          'refusal',
          isA<NotYaml>().having(
            (NotYaml n) => n.reason,
            'reason',
            'byte 16: Invalid UTF-8 byte',
          ),
        ),
      );
    });

    test('on a key muster does not know, naming its path', () async {
      final GitCodebase app = await codebaseNamed('app');
      final (String name, List<Field> fields) = entryOf(app);
      await writeFile(
        atRoot(temp),
        renderManifest([
          (name, [...fields, ('depth', '1')]),
        ]),
      );
      await refuses(
        isA<ManifestInvalid>().having(
          (ManifestInvalid i) => i.refusal,
          'refusal',
          isA<UnknownKey>().having(
            (UnknownKey u) => u.path,
            'path',
            pathOf(['codebases', 'app', 'depth']),
          ),
        ),
      );
    });

    test('on a git URL holding a line break, naming its path', () async {
      final GitCodebase app = await codebaseNamed('app');
      final (String name, List<Field> fields) = entryOf(app);
      await writeFile(
        atRoot(temp),
        renderManifest([
          (
            name,
            [
              for (final Field field in fields)
                field.$1 == 'git' ? ('git', '${field.$2}\n') : field,
            ],
          ),
        ]),
      );
      await refuses(
        isA<ManifestInvalid>().having(
          (ManifestInvalid i) => i.refusal,
          'refusal',
          isA<BadValue>()
              .having(
                (BadValue b) => b.path,
                'path',
                pathOf(['codebases', 'app', 'git']),
              )
              .having((BadValue b) => b.wanted, 'wanted', Wanted.gitUrl),
        ),
      );
    });

    test('on a root holding a line break, naming its path', () async {
      final GitCodebase app = await codebaseNamed('app');
      final (String name, List<Field> fields) = entryOf(app);
      await writeFile(
        atRoot(temp),
        renderManifest([
          (
            name,
            [
              for (final Field field in fields)
                if (field.$1 != 'root') field,
              ('root', '${app.root.path}\n'),
            ],
          ),
        ]),
      );
      await refuses(
        isA<ManifestInvalid>().having(
          (ManifestInvalid i) => i.refusal,
          'refusal',
          isA<BadValue>()
              .having(
                (BadValue b) => b.path,
                'path',
                pathOf(['codebases', 'app', 'root']),
              )
              .having(
                (BadValue b) => b.wanted,
                'wanted',
                Wanted.rootInsideRepo,
              ),
        ),
      );
    });

    test('on a name met in two manifests, naming it and both', () async {
      final GitCodebase app = await codebaseNamed('app');
      final String listed = p.join(temp.path, 'listed.yaml');
      await writeManifest(atRoot(temp), [app]);
      await writeManifest(listed, [await codebaseNamed('b'), app]);
      await refuses(
        isA<CodebaseNamedTwice>()
            .having((CodebaseNamedTwice n) => n.name.name, 'name', 'app')
            .having(
              (CodebaseNamedTwice n) => n.first.path,
              'first',
              atRoot(temp),
            )
            .having((CodebaseNamedTwice n) => n.second.path, 'second', listed),
        variables: {'MUSTER_MANIFESTS': listed},
      );
    });

    for (final Os os in Os.values) {
      test('with no cache to clone into, naming the system its environment '
          'is of, $os', () async {
        await writeManifest(atRoot(temp), [await codebaseNamed('app')]);
        runner.commands.clear();
        final Load refused = await Loader(
          (variables: const {}, os: os),
          .new(consumerIn(temp).path, .posix),
          runner,
          .new(testLocker),
          scratchesIn(temp),
        ).load(named: [atRoot(temp)]);
        expect(
          refused,
          refusedFor(isA<NoCache>().having((NoCache n) => n.os, 'os', os)),
        );
        expect(runner.given, isEmpty);
      });
    }
  });

  group('Muster.load, reading the process itself,', () {
    test('loads a manifest named, with no codebases', () async {
      final String manifest = p.join(temp.path, 'empty.yaml');
      await writeManifest(manifest, []);
      expect(await Muster.load(manifests: [manifest]), loadedWith({}));
    });

    test(
      'refuses where the working directory is gone, throwing nothing',
      () async {
        final String manifest = p.join(temp.path, 'empty.yaml');
        await writeManifest(manifest, []);
        final ProcessResult ran = await probeGone(temp, .fetch, manifest);
        expect(ran.stdout, 'NoWorkingDirectory', reason: '${ran.stderr}');
      },
    );

    test('refuses a manifest whose file name does not end .yaml', () async {
      expect(
        await Muster.load(manifests: [p.join(temp.path, 'muster.json')]),
        refusedFor(isA<NotManifestName>()),
      );
    });
  });

  test('a git pin tracking a file named `example` has no example, and loads '
      'as one holding none, again over its checkout, the file kept as the '
      "pin's", () async {
    final GitCodebase app = await codebaseNamed('app', {
      ...packageFiles('app'),
      'example': 'a file\n',
    });
    await writeManifest(atRoot(temp), [app]);
    final Matcher fetched = loadedWith({
      'app': isA<Fetched>().having(
        (Fetched f) => f.example,
        'example',
        const NoExample(),
      ),
    });
    expect(await load(), fetched);
    expect(await load(), fetched);
    expect(
      await File(p.join(checkoutOf('app'), 'example')).readAsString(),
      'a file\n',
    );
  });
}

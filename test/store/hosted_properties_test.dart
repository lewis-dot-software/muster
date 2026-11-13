import 'dart:convert';
import 'dart:io';

import 'package:glados/glados.dart';
import 'package:muster/src/model/around_pubspec.dart';
import 'package:muster/src/model/checkout.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/fetch_outcome.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/package_path.dart';
import 'package:muster/src/model/pubspec_overrides.dart';
import 'package:muster/src/model/resolution.dart';
import 'package:muster/src/store/checkouts.dart';
import 'package:muster/src/store/store_fault.dart';
import 'package:path/path.dart' as p;

import '../support/files_under.dart';
import '../support/git.dart';
import '../support/hosted.dart' as hosted show lockedCheckout;
import '../support/hosted.dart' hide lockedCheckout;
import '../support/loads.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
import '../support/shrinking_at_most.dart';
import '../support/spy_runner.dart';
import '../support/tree_under.dart';
import '../support/write_file.dart';

/// The files a package may serve beside its pubspec: the plain ones, each
/// drawn or not, then the three a row of [_closed] serves or not.
const List<String> _pool = [
  'lib/a.dart',
  'lib/src/b.dart',
  'bin/tool.dart',
  'test/a_test.dart',
  'tool/run.sh',
  'README.md',
  'analysis_options.yaml',
  '.gitignore',
  'pubspec.lock',
  'example/pubspec.lock',
  'example/pubspec_overrides.yaml',
];

/// What stood in a checkout before it was made afresh.
enum _Before {
  /// Nothing.
  nothing,

  /// A file of its own in the checkout's top and one in its package.
  strays,

  /// The checkout of the package by the other resolution, its stamp gone.
  otherResolution,
}

/// A package's shape: how it resolves, whether it serves an example, whether
/// it and its example are members of a pub workspace, which of [_pool] it
/// serves and a seed for their contents.
typedef _Shape = ({
  Resolution resolution,
  bool example,
  bool workspace,
  Set<int> pool,
  int seed,
});

/// A shape's closed choices: how it resolves, whether it serves an example,
/// whether it is a workspace's member, and whether it serves a root lock, an
/// example lock and example overrides.
typedef _Closed = ({
  Resolution resolution,
  bool example,
  bool workspace,
  bool lock,
  bool exampleLock,
  bool exampleOverrides,
});

/// Every shape's closed choices a property takes, in rows where each value of
/// each choice, and each pair of values of any two, meets in one at least, so
/// none is left to the draws.
const List<_Closed> _closed = [
  (
    resolution: .alone,
    example: false,
    workspace: false,
    lock: false,
    exampleLock: false,
    exampleOverrides: false,
  ),
  (
    resolution: .alone,
    example: false,
    workspace: false,
    lock: false,
    exampleLock: true,
    exampleOverrides: true,
  ),
  (
    resolution: .alone,
    example: true,
    workspace: true,
    lock: true,
    exampleLock: false,
    exampleOverrides: false,
  ),
  (
    resolution: .asDependency,
    example: false,
    workspace: true,
    lock: true,
    exampleLock: false,
    exampleOverrides: true,
  ),
  (
    resolution: .asDependency,
    example: true,
    workspace: false,
    lock: true,
    exampleLock: true,
    exampleOverrides: false,
  ),
  (
    resolution: .asDependency,
    example: true,
    workspace: true,
    lock: false,
    exampleLock: true,
    exampleOverrides: true,
  ),
];

/// A shape's open choices: which plain files of [_pool] it serves, and a seed
/// for their contents.
typedef _Open = ({Set<int> plain, int seed});

final Generator<_Open> _open = any.combine2(
  any.set(any.intInRange(0, _pool.indexOf('pubspec.lock'))),
  any.intInRange(0, 1000),
  (Set<int> plain, int seed) => (plain: plain, seed: seed),
);

/// The shape of each row of [_closed], beside [open].
List<_Shape> _shapesOf(_Open open) => [
  for (final _Closed closed in _closed)
    (
      resolution: closed.resolution,
      example: closed.example,
      workspace: closed.workspace,
      pool: {
        ...open.plain,
        if (closed.lock) _pool.indexOf('pubspec.lock'),
        if (closed.exampleLock) _pool.indexOf('example/pubspec.lock'),
        if (closed.exampleOverrides)
          _pool.indexOf('example/pubspec_overrides.yaml'),
      },
      seed: open.seed,
    ),
];

/// Each set of packages a property may take away, so a property reaches
/// every one whatever glados draws.
const List<Set<Package>> _subsets = [
  {},
  {.root},
  {.example},
  {.root, .example},
];

/// The files the package `a` of [shape] serves at `1.0.0`, a lock among them
/// one pub reads.
Map<String, String> _served(_Shape shape) => {
  'pubspec.yaml': hostedPubspec('a', '1.0.0', workspace: shape.workspace),
  if (shape.example)
    'example/pubspec.yaml': examplePubspec('a', workspace: shape.workspace),
  for (final int i in shape.pool)
    _pool[i]: switch (p.posix.basename(_pool[i])) {
      'pubspec.lock' => '# served $i of ${shape.seed}\n$lockText',
      // As a package serves one: its package by a path of its own spelling.
      'pubspec_overrides.yaml' =>
        '# served $i of ${shape.seed}\n'
            '${shape.workspace ? 'resolution:\n' : ''}'
            'dependency_overrides:\n'
            '  a:\n'
            '    path: ../\n',
      _ => 'file $i of ${shape.seed}\n',
    },
};

/// Whether the package of [shape] serves overrides in its [package].
bool _servesOverrides(_Shape shape, Package package) => switch (package) {
  .root => false,
  .example => shape.pool.contains(
    _pool.indexOf('example/pubspec_overrides.yaml'),
  ),
};

/// The packages of [shape]: the root, and the example where it serves one.
Set<Package> _packages(_Shape shape) => {.root, if (shape.example) .example};

/// A bench for one draw: a package server, the checkouts of a consumer that
/// fetch from it, and what a test reads of them.
class _Bench {
  _Bench._(this.temp, this.server, this.runner, this.checkouts, this.locks);

  static Future<_Bench> make(Directory temp) async {
    final PackageServer server = await .start();
    final SpyRunner runner = .new({
      ...hermetic(temp),
      ...pubVariables(temp, server),
    });
    return ._(
      temp,
      server,
      runner,
      checkoutsIn(temp, runner),
      locksBeside(atRoot(temp)),
    );
  }

  final Directory temp;
  final PackageServer server;
  final SpyRunner runner;
  final Checkouts checkouts;
  final LocksDirectory locks;

  /// The checkout of the codebase `app`.
  CheckoutPath get checkout => appCheckout(checkouts);

  /// A new consumer's checkouts in the same directory, which have read no
  /// SDK's version yet.
  Checkouts get fresh => checkoutsIn(temp, runner);

  /// [codebase]'s kept locks written, then its checkout made on them.
  Future<Checkout> lockedCheckout(HostedCodebase codebase) =>
      hosted.lockedCheckout(checkouts, locks, codebase);

  /// Whether any command given since [from] unpacked a package.
  bool unpackedSince(int from) => runner.given
      .skip(from)
      .any((String command) => command.startsWith('dart pub unpack'));

  Future<void> close() => server.close();
}

/// [body] run on a bench of its own in a directory of its own.
Future<void> _onBench(Future<void> Function(_Bench bench) body) =>
    inTemp((Directory temp) async {
      final _Bench bench = await .make(temp);
      try {
        await body(bench);
      } finally {
        await bench.close();
      }
    });

/// One way a checkout can fall off what was stamped.
enum _Off {
  /// The stamp deleted.
  stampGone,

  /// The stamp's text no stamp.
  stampGarbled,

  /// The stamp naming another version.
  stampElsewhere,

  /// The root's lock rewritten.
  rootLock,

  /// The root's `package_config.json` rewritten.
  rootConfig,

  /// The root's `package_config.json` deleted.
  rootConfigGone,

  /// The example's lock rewritten.
  exampleLock,

  /// The example's `package_config.json` rewritten.
  exampleConfig;

  /// Whether the off lands on the example, which a package may not serve.
  bool get example => switch (this) {
    .exampleLock || .exampleConfig => true,
    .stampGone ||
    .stampGarbled ||
    .stampElsewhere ||
    .rootLock ||
    .rootConfig ||
    .rootConfigGone => false,
  };
}

void main() {
  Glados(_open.shrinkingAtMost(gitTries), .new(numRuns: 1)).test(
    'A hosted checkout made afresh holds every file pub serves for the '
    'package at its version, unchanged but for a `pubspec.lock` its resolve '
    'replaces, and nothing beside them but what the resolve, the package '
    "around it and each package's `pubspec_overrides.yaml` write.",
    (_Open open) async {
      for (final (_Shape shape, _Before before) in [
        for (final _Shape shape in _shapesOf(open))
          for (final _Before before in _Before.values) (shape, before),
      ]) {
        await _onBench((_Bench bench) async {
          bench.server.serve('a', '1.0.0', _served(shape));
          final HostedCodebase codebase = hostedOf(
            'a',
            resolution: shape.resolution,
          );
          switch (before) {
            case .nothing:
              break;
            case .strays:
              await writeFile(fileIn(bench.checkout, 'stray.txt'), 'stray\n');
              await writeFile(
                fileIn(bench.checkout, 'a-1.0.0/lib/stray.dart'),
                'stray\n',
              );
            case .otherResolution:
              await bench.lockedCheckout(
                hostedOf(
                  'a',
                  resolution: switch (shape.resolution) {
                    .alone => .asDependency,
                    .asDependency => .alone,
                  },
                ),
              );
              await File(bench.checkout.stamp.path).delete();
          }
          final Checkout checkout = await bench.lockedCheckout(codebase);
          expect(
            checkout.package.path,
            PackagePath.unpacked(bench.checkout, codebase).path,
          );
          final List<String> resolved = resolvedIn(
            bench.checkout,
            codebase,
            _packages(shape),
          );
          for (final String lock in resolved.where(
            (String path) => path.endsWith('pubspec.lock'),
          )) {
            expect(await File(fileIn(bench.checkout, lock)).exists(), isTrue);
          }
          expect(await filesUnder(bench.checkout.path, less: resolved), {
            for (final MapEntry<String, String>(:key, :value) in _served(
              shape,
            ).entries)
              if (!resolved.contains('a-1.0.0/$key')) 'a-1.0.0/$key': value,
            if (shape.resolution == .asDependency)
              'pubspec.yaml': aroundPubspec(codebase),
            for (final Package package in _packages(shape))
              if (pubspecOverrides(
                    codebase,
                    package,
                    member: shape.workspace,
                    holding: _servesOverrides(shape, package),
                  )
                  case final String overrides)
                p.posix.relative(
                  p.posix.joinAll(
                    p.split(
                      PackagePath.ofHosted(
                        bench.checkout,
                        codebase,
                        package,
                      ).overrides.path,
                    ),
                  ),
                  from: p.posix.joinAll(p.split(bench.checkout.path)),
                ): overrides,
          }, reason: '$before');
        });
      }
    },
  );

  Glados(
    any
        .combine2(
          any.set(any.choose(['r', 's'])),
          any.set(any.choose(['d', 'e'])),
          (Set<String> dependencies, Set<String> dev) =>
              (dependencies: dependencies, dev: dev),
        )
        .shrinkingAtMost(gitTries),
    .new(numRuns: 3),
  ).test(
    'A package resolved `alone` resolves with its dev dependencies, and one '
    'resolved `as-dependency` without them.',
    (({Set<String> dependencies, Set<String> dev}) drawn) async {
      // Every resolution and membership, so none is left to the draws.
      for (final Resolution resolution in Resolution.values) {
        for (final bool workspace in [false, true]) {
          final ({
            Resolution resolution,
            Set<String> dependencies,
            Set<String> dev,
            bool workspace,
          })
          draw = (
            resolution: resolution,
            dependencies: drawn.dependencies,
            dev: drawn.dev,
            workspace: workspace,
          );
          await _onBench((_Bench bench) async {
            bench.server.serve('a', '1.0.0', {
              'pubspec.yaml': hostedPubspec(
                'a',
                '1.0.0',
                workspace: draw.workspace,
                dependencies: {
                  for (final String d in draw.dependencies) d: '^1.0.0',
                },
                devDependencies: {
                  for (final String d in draw.dev) d: '^1.0.0',
                  // A dev dependency no host serves, which only a resolve
                  // without dev dependencies passes by.
                  if (draw.resolution == .asDependency) 'unserved': '^1.0.0',
                },
              ),
            });
            for (final String leaf in {...draw.dependencies, ...draw.dev}) {
              serveLeaf(bench.server, leaf, '1.0.0');
            }
            final HostedCodebase codebase = hostedOf(
              'a',
              resolution: draw.resolution,
            );
            await bench.lockedCheckout(codebase);
            expect(
              await configuredIn(.ofHosted(bench.checkout, codebase, .root)),
              {
                'a',
                ...draw.dependencies,
                ...switch (draw.resolution) {
                  .alone => draw.dev,
                  .asDependency => {aroundName},
                },
              },
            );
          });
        }
      }
    },
  );

  Glados(
    any.intInRange(1, 4).shrinkingAtMost(gitTries),
    .new(numRuns: 2),
  ).test('A package resolved `as-dependency` resolves where one of its own '
      'dependencies depends back on it from pub.dev.', (int depth) async {
    // Every constraint, with an example and without, so none is left to
    // the draws.
    for (final String constraint in ['any', '^1.0.0', '>=9.0.0']) {
      for (final bool example in [false, true]) {
        final ({int depth, String constraint, bool example}) draw = (
          depth: depth,
          constraint: constraint,
          example: example,
        );
        await _onBench((_Bench bench) async {
          // `a` depends on `c1`, each `c<n>` on the next, and the last back on
          // `a` from the host, by each constraint in turn.
          bench.server.serve('a', '1.0.0', {
            'pubspec.yaml': hostedPubspec(
              'a',
              '1.0.0',
              dependencies: {'c1': '^1.0.0'},
            ),
            // An example resolves alone, the cycle through `c1` beside it.
            if (draw.example) 'example/pubspec.yaml': examplePubspec('a'),
          });
          for (int n = 1; n <= draw.depth; n++) {
            bench.server.serve('c$n', '1.0.0', {
              'pubspec.yaml': hostedPubspec(
                'c$n',
                '1.0.0',
                dependencies: n == draw.depth
                    ? {'a': draw.constraint}
                    : {'c${n + 1}': '^1.0.0'},
              ),
            });
          }
          final HostedCodebase codebase = hostedOf(
            'a',
            resolution: .asDependency,
          );
          final Checkout checkout = await bench.lockedCheckout(codebase);
          final Map<String, Object?> config = jsonDecode(
            await File(
              PackagePath.ofHosted(
                bench.checkout,
                codebase,
                .root,
              ).packageConfig.path,
            ).readAsString(),
          ) as Map<String, Object?>;
          final Map<String, Object?> a = (config['packages']! as List<Object?>)
              .cast<Map<String, Object?>>()
              .singleWhere(
                (Map<String, Object?> entry) => entry['name'] == 'a',
              );
          expect(
            p.normalize(
              p.join(
                p.dirname(
                  PackagePath.ofHosted(
                    bench.checkout,
                    codebase,
                    .root,
                  ).packageConfig.path,
                ),
                a['rootUri']! as String,
              ),
            ),
            checkout.package.path,
          );
        });
      }
    }
  });

  Glados(_open.shrinkingAtMost(gitTries), .new(numRuns: 2)).test(
    'A second checkout of a hosted codebase hands the first out untouched, '
    'unpacking and resolving nothing.',
    (_Open open) async {
      for (final _Shape shape in _shapesOf(open)) {
        await _onBench((_Bench bench) async {
          bench.server.serve('a', '1.0.0', _served(shape));
          final HostedCodebase codebase = hostedOf(
            'a',
            resolution: shape.resolution,
          );
          final Checkout first = await bench.lockedCheckout(codebase);
          final Map<String, String> tree = await treeUnder(bench.checkout.path);
          final String stamp = await File(bench.checkout.stamp.path)
              .readAsString();
          bench.runner.commands.clear();
          final Checkout second = await bench.fresh.checkout(
            Hosted(codebase),
            bench.locks,
          );
          expect(bench.runner.given, ['dart --version']);
          expect(second, first);
          expect(await treeUnder(bench.checkout.path), tree);
          expect(await File(bench.checkout.stamp.path).readAsString(), stamp);
        });
      }
    },
  );

  Glados(_open.shrinkingAtMost(gitTries), .new(numRuns: 1)).test(
    'A hosted checkout whose stamp, lock or `package_config.json` differs '
    'from what was stamped is unpacked afresh.',
    (_Open open) async {
      for (final _Shape shape in _shapesOf(open)) {
        await _onBench((_Bench bench) async {
          bench.server.serve('a', '1.0.0', _served(shape));
          final HostedCodebase codebase = hostedOf(
            'a',
            resolution: shape.resolution,
          );
          await bench.lockedCheckout(codebase);
          PackagePath of(Package package) =>
              .ofHosted(bench.checkout, codebase, package);
          final String marker = fileIn(bench.checkout, 'a-1.0.0/marker.txt');
          // Each off alone, on a checkout that stands once the last is made
          // again.
          for (final _Off off in _Off.values) {
            if (off.example && !shape.example) {
              continue;
            }
            await writeFile(marker, 'not served\n');
            switch (off) {
              case .stampGone:
                await File(bench.checkout.stamp.path).delete();
              case .stampGarbled:
                await writeFile(bench.checkout.stamp.path, 'garbled\n');
              case .stampElsewhere:
                final Map<String, Object?> stamp = jsonDecode(
                  await File(bench.checkout.stamp.path).readAsString(),
                ) as Map<String, Object?>;
                await writeFile(
                  bench.checkout.stamp.path,
                  jsonEncode(stamp..['version'] = '2.0.0'),
                );
              case .rootLock:
                await writeFile(of(.root).lock.path, 'packages: {}\n');
              case .rootConfig:
                await writeFile(of(.root).packageConfig.path, '{}\n');
              case .rootConfigGone:
                await File(of(.root).packageConfig.path).delete();
              case .exampleLock:
                await writeFile(of(.example).lock.path, 'packages: {}\n');
              case .exampleConfig:
                await writeFile(of(.example).packageConfig.path, '{}\n');
            }
            final int from = bench.runner.commands.length;
            await bench.fresh.checkout(Hosted(codebase), bench.locks);
            expect(bench.unpackedSince(from), isTrue, reason: '$off');
            expect(await File(marker).exists(), isFalse, reason: '$off');
            for (final Package package in _packages(shape)) {
              expect(
                await File(of(package).lock.path).readAsString(),
                await File(
                  KeptLockPath.of(bench.locks, Hosted(codebase), package).path,
                ).readAsString(),
                reason: '$off',
              );
            }
          }
        });
      }
    },
  );

  Glados(
    _open.shrinkingAtMost(gitTries),
    .new(numRuns: 1),
  ).test('A package and its example each resolve on their own kept lock, and a '
      'lock that is missing gives `Unlocked`, naming it.', (_Open open) async {
    for (final _Shape shape in _shapesOf(open)) {
      for (final Set<Package> gone in _subsets) {
        await _onBench((_Bench bench) async {
          // The example depends on a package the root does not, so its lock is
          // its own.
          bench.server.serve('a', '1.0.0', {
            ..._served(shape),
            if (shape.example)
              'example/pubspec.yaml':
                  '${examplePubspec('a', workspace: shape.workspace)}'
                  '  only_example: ^1.0.0\n',
          });
          serveLeaf(bench.server, 'only_example', '1.0.0');
          final HostedCodebase codebase = hostedOf(
            'a',
            resolution: shape.resolution,
          );
          expect(await bench.checkouts.lock(Hosted(codebase), bench.locks), [
            for (final Package package in _packages(shape))
              KeptLockPath.of(bench.locks, Hosted(codebase), package),
          ]);
          for (final Package package in gone) {
            final File kept = .new(
              KeptLockPath.of(bench.locks, Hosted(codebase), package).path,
            );
            if (await kept.exists()) {
              await kept.delete();
            }
          }
          final List<Package> lacking = [
            for (final Package package in Package.values)
              if (_packages(shape).contains(package) && gone.contains(package))
                package,
          ];
          final Future<Checkout> made = bench.checkouts.checkout(
            Hosted(codebase),
            bench.locks,
          );
          if (lacking.isNotEmpty) {
            await expectLater(
              made,
              throwsA(
                isA<StoreFault>().having(
                  (StoreFault f) => f.failure,
                  'failure',
                  isA<Unlocked>().having(
                    (Unlocked u) => u.lock,
                    'lock',
                    KeptLockPath.of(
                      bench.locks,
                      Hosted(codebase),
                      lacking.first,
                    ),
                  ),
                ),
              ),
            );
            return;
          }
          await made;
          final Map<Package, String> locks = {
            for (final Package package in _packages(shape))
              package: await File(
                PackagePath.ofHosted(
                  bench.checkout,
                  codebase,
                  package,
                ).lock.path,
              ).readAsString(),
          };
          for (final MapEntry<Package, String>(key: package, value: lock)
              in locks.entries) {
            expect(
              lock,
              await File(
                KeptLockPath.of(bench.locks, Hosted(codebase), package).path,
              ).readAsString(),
            );
          }
          if (shape.example) {
            expect(locks[Package.example], contains('only_example'));
            expect(locks[Package.root], isNot(contains('only_example')));
          }
        });
      }
    }
  });

  Glados(
    any
        .combine3(
          any.choose(Resolution.values),
          any.intInRange(1, 3),
          any.bool,
          (Resolution resolution, int count, bool again) =>
              (resolution: resolution, count: count, again: again),
        )
        .shrinkingAtMost(gitTries),
    .new(numRuns: 8),
  ).test(
    'A hosted codebase\'s checkout takes no clone\'s claim and starts no git.',
    (({Resolution resolution, int count, bool again}) draw) => _onBench((
      _Bench bench,
    ) async {
      for (int n = 0; n < draw.count; n++) {
        serveLeaf(bench.server, 'p$n', '1.0.0');
        final HostedCodebase codebase = hostedOf(
          'p$n',
          name: 'app$n',
          resolution: draw.resolution,
        );
        await bench.lockedCheckout(codebase);
        if (draw.again) {
          await bench.fresh.checkout(Hosted(codebase), bench.locks);
        }
      }
      expect(
        bench.runner.commands.where((command) => command.executable == .git),
        isEmpty,
      );
      expect(
        await Directory(cacheDirectoryIn(bench.temp).path).exists(),
        isFalse,
      );
    }),
  );
}

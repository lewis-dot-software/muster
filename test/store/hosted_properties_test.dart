import 'dart:convert';
import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/src/model/around_pubspec.dart';
import 'package:muster/src/model/checkout.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/example.dart';
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
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/faults.dart';
import '../support/files_under.dart';
import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/hosted.dart' as hosted show lockedCheckout;
import '../support/hosted.dart' hide lockedCheckout;
import '../support/loads.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
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

/// A path dependency an example may take beside its package: its [name],
/// its [path] and whether that path leaves the package.
typedef _Dependency = ({String name, String path, bool outside});

/// The path dependencies a property draws for an example: one inside the
/// package that it serves, one above it and one absolute, neither served.
const List<_Dependency> _extraDependencies = [
  (name: 'b', path: '../packages/b', outside: false),
  (name: 'c', path: '../../c', outside: true),
  (name: 'd', path: '/d', outside: true),
];

/// Each way an example whose every path stays inside its package fails to
/// resolve.
enum _Unresolvable {
  /// A dependency no host serves.
  unserved,

  /// A dependency served at no version its constraint takes.
  unsatisfied,

  /// A path inside the package that it does not serve.
  missingInside,

  /// A pubspec that is no YAML.
  notYaml,
}

/// Each way pub refuses an example's pubspec or its served overrides, each
/// beside a path dependency that leaves the package.
enum _Refusal {
  /// A pubspec that is no YAML, its served overrides holding the path.
  notYaml,

  /// A pubspec that is a YAML list, its served overrides holding the path.
  notMap,

  /// A pubspec with no `name`.
  noName,

  /// A `dev_dependencies` that is no map.
  sectionNotMap,

  /// A dependency whose name is no package name.
  invalidName,

  /// A dependency on the example itself.
  selfDependency,

  /// A version constraint pub cannot read.
  badConstraint,

  /// A dependency by two sources.
  twoSources,

  /// A path that is no string.
  pathNotString,

  /// Served overrides that are no YAML map.
  servedNotMap,

  /// Served overrides holding a field pub does not read.
  servedField,

  /// Served overrides whose entry names no package.
  servedName,
}

/// The files of the example of the package `a`, refused by pub for
/// [refusal], or pub's to resolve where it is null, beside a dependency `c`
/// at [outside], a path that leaves the package, after the refused entry
/// where [first] holds and before it else.
Map<String, String> _refusedExample(
  _Refusal? refusal,
  String outside,
  bool first,
) {
  final String leaving = '  c:\n    path: ${jsonEncode(outside)}\n';
  final String refused = switch (refusal) {
    .invalidName || .servedName => '  my-b: any\n',
    .selfDependency => '  a_example:\n    path: .\n',
    .badConstraint => '  b: notaversion\n',
    .twoSources =>
      '  b:\n    path: ../packages/b\n    git: https://example.com/b.git\n',
    .pathNotString => '  b:\n    path: 3\n',
    .notYaml ||
    .notMap ||
    .noName ||
    .sectionNotMap ||
    .servedNotMap ||
    .servedField ||
    null => '',
  };
  final String entries = first ? '$refused$leaving' : '$leaving$refused';
  return {
    'example/pubspec.yaml': switch (refusal) {
      .notYaml => 'name: [a_example\n',
      .notMap => '- a_example\n',
      _ => [
        if (refusal != .noName) 'name: a_example\n',
        'environment:\n  sdk: ^3.0.0\n',
        'dependencies:\n  a:\n    path: ..\n',
        switch (refusal) {
          .servedName || .servedNotMap || .servedField => leaving,
          _ => entries,
        },
        if (refusal == .sectionNotMap) 'dev_dependencies: 3\n',
      ].join(),
    },
    if (switch (refusal) {
          .notYaml ||
          .notMap => 'dependency_overrides:\n  a:\n    path: ..\n$leaving',
          .servedNotMap => '- c\n',
          .servedField => 'foo: 1\n',
          .servedName => 'dependency_overrides:\n$entries',
          .noName ||
          .sectionNotMap ||
          .invalidName ||
          .selfDependency ||
          .badConstraint ||
          .twoSources ||
          .pathNotString ||
          null => null,
        }
        case final String served)
      'example/pubspec_overrides.yaml': served,
  };
}

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

/// A shape's open choices, each plain file of [_pool] served or not and a
/// seed below 1000.
final Gen<_Open> _open = .build(
  (Draw draw) => (
    plain: draw(.set(.integer(min: 0, max: _pool.indexOf('pubspec.lock') - 1))),
    seed: draw(.integer(min: 0, max: 999)),
  ),
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
/// every one whatever its draws.
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

/// A bench for one run: a package server, the checkouts of a consumer that
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
  property('A hosted checkout made afresh holds every file pub serves for the '
      'package at its version, unchanged but for a `pubspec.lock` its resolve '
      'replaces, and nothing beside them but what the resolve, the package '
      "around it and each package's `pubspec_overrides.yaml` write.", (
    Draw draw,
  ) async {
    final _Open open = draw(_open, label: 'open');
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
          unpackedPackage(bench.checkout, codebase).path,
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
                  published: (member: shape.workspace, overrides: false),
                  holding: _servesOverrides(shape, package),
                )
                case final String overrides)
              p.posix.relative(
                p.posix.joinAll(
                  p.split(
                    hostedPackage(
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
  }, settings: .new(runs: 1, shrinkSteps: gitShrinks));

  property(
    'A package resolved `alone` resolves with its dev dependencies, and one '
    'resolved `as-dependency` without them.',
    (Draw draw) async {
      final Set<String> dependencies = draw(
        .set(.element(['r', 's'])),
        label: 'dependencies',
      );
      final Set<String> dev = draw(.set(.element(['d', 'e'])), label: 'dev');
      // Every resolution and membership, so none is left to the draws.
      for (final Resolution resolution in Resolution.values) {
        for (final bool workspace in [false, true]) {
          await _onBench((_Bench bench) async {
            bench.server.serve('a', '1.0.0', {
              'pubspec.yaml': hostedPubspec(
                'a',
                '1.0.0',
                workspace: workspace,
                dependencies: {
                  for (final String d in dependencies) d: '^1.0.0',
                },
                devDependencies: {
                  for (final String d in dev) d: '^1.0.0',
                  // A dev dependency no host serves, which only a resolve
                  // without dev dependencies passes by.
                  if (resolution == .asDependency) 'unserved': '^1.0.0',
                },
              ),
            });
            for (final String leaf in {...dependencies, ...dev}) {
              serveLeaf(bench.server, leaf, '1.0.0');
            }
            final HostedCodebase codebase = hostedOf(
              'a',
              resolution: resolution,
            );
            await bench.lockedCheckout(codebase);
            expect(
              await configuredIn(
                hostedPackage(bench.checkout, codebase, .root),
              ),
              {
                'a',
                ...dependencies,
                ...switch (resolution) {
                  .alone => dev,
                  .asDependency => {aroundName},
                },
              },
            );
          });
        }
      }
    },
    settings: .new(runs: 3, shrinkSteps: gitShrinks),
  );

  property('A hosted package resolved `alone` resolves with none of the '
      '`dependency_overrides` its pubspec publishes.', (Draw draw) async {
    final Set<String> overridden = draw(
      .set(.element(['r', 'd', 'o'])),
      label: 'overridden',
    );
    // Every membership, so none is left to the draws.
    for (final bool workspace in [false, true]) {
      await _onBench((_Bench bench) async {
        // `r` a dependency, `d` a dev dependency and `o` neither, each
        // drawn overridden to a path the package does not ship, which only
        // a resolve without the overrides passes by.
        bench.server.serve('a', '1.0.0', {
          'pubspec.yaml': hostedPubspec(
            'a',
            '1.0.0',
            workspace: workspace,
            dependencies: {'r': '^1.0.0'},
            devDependencies: {'d': '^1.0.0'},
            dependencyOverrides: {
              for (final String d in overridden) d: '../unshipped_$d',
            },
          ),
        });
        for (final String leaf in ['r', 'd', 'o']) {
          serveLeaf(bench.server, leaf, '1.0.0');
        }
        final HostedCodebase codebase = hostedOf('a');
        await bench.lockedCheckout(codebase);
        final PackagePath root = hostedPackage(bench.checkout, codebase, .root);
        expect(await configuredIn(root), {'a', 'r', 'd'});
        expect(
          await File(root.lock.path).readAsString(),
          isNot(contains('source: path')),
        );
      });
    }
  }, settings: .new(runs: 3, shrinkSteps: gitShrinks));

  property(
    "A hosted package's example is left unresolved exactly when its pubspec "
    'path-depends outside the package on a package muster does not override '
    "to the package's own path, and `Fetched` says which.",
    (Draw draw) async {
      final List<_Dependency> drawnExtra = draw(
        .list(.element(_extraDependencies)),
        label: 'drawnExtra',
      ).toSet().toList();
      final bool drawnSelfOutside = draw(.boolean(), label: 'drawnSelfOutside');
      // Rows where each kind of dependency set, each value of the package's
      // own path and each membership meets every other in one at least, the
      // draw's own beside them, each under every resolution, so none is left
      // to the draws: an example with no path but the package's, one inside,
      // the package's own path above it, and one outside, first or after one
      // inside, and an overrides file served empty of YAML, which pub reads
      // as none, so the package's own path and its membership are left out
      // beside it.
      for (final (
            Resolution resolution,
            List<_Dependency> extra,
            bool selfOutside,
            bool workspace,
            String? served,
          )
          in [
            for (final Resolution resolution in Resolution.values)
              for (final (
                    List<_Dependency> extra,
                    bool selfOutside,
                    bool workspace,
                    String? served,
                  )
                  in [
                    (const <_Dependency>[], false, false, null),
                    (const <_Dependency>[], true, true, null),
                    ([_extraDependencies[0]], false, true, null),
                    ([_extraDependencies[0]], true, false, null),
                    (
                      [_extraDependencies[1], _extraDependencies[0]],
                      false,
                      false,
                      null,
                    ),
                    (
                      [_extraDependencies[0], _extraDependencies[2]],
                      true,
                      true,
                      null,
                    ),
                    ([_extraDependencies[1]], false, false, ''),
                    ([_extraDependencies[0]], false, false, '# served\n'),
                    (drawnExtra, drawnSelfOutside, false, null),
                  ])
                (resolution, extra, selfOutside, workspace, served),
          ]) {
        await _onBench((_Bench bench) async {
          bench.server.serve('a', '1.0.0', {
            'pubspec.yaml': hostedPubspec('a', '1.0.0', workspace: workspace),
            'packages/b/pubspec.yaml': pubspecOf('b'),
            'example/pubspec.yaml': [
              'name: a_example',
              'environment:',
              '  sdk: ^3.${workspace ? 6 : 0}.0',
              if (workspace) 'resolution: workspace',
              'dependencies:',
              '  a:',
              '    path: ${selfOutside ? '../../a' : '..'}',
              for (final _Dependency(:name, :path) in extra) ...[
                '  $name:',
                '    path: $path',
              ],
              '',
            ].join('\n'),
            'example/pubspec_overrides.yaml': ?served,
          });
          final HostedCodebase codebase = hostedOf('a', resolution: resolution);
          final _Dependency? first = extra
              .where((_Dependency d) => d.outside)
              .firstOrNull;
          final PackagePath example = hostedPackage(
            bench.checkout,
            codebase,
            .example,
          );
          expect(await bench.checkouts.lock(Hosted(codebase), bench.locks), [
            keptLockOf(bench.locks, Hosted(codebase), .root),
            if (first == null)
              keptLockOf(bench.locks, Hosted(codebase), .example),
          ]);
          final Checkout checkout = await bench.checkouts.checkout(
            Hosted(codebase),
            bench.locks,
          );
          expect(checkout.example, switch (first) {
            _Dependency(:final name, :final path) => ExampleUnresolved((
              dependency: .parse(name)!,
              path: path,
            )),
            null => ExampleResolved(example),
          });
          expect(
            await File(
              hostedPackage(bench.checkout, codebase, .root).packageConfig.path,
            ).exists(),
            isTrue,
          );
          expect(
            await File(example.packageConfig.path).exists(),
            first == null,
          );
          expect(
            await File(example.overrides.path).exists(),
            first == null || served != null,
          );
          expect(
            (await bench.fresh.checkout(Hosted(codebase), bench.locks)).example,
            checkout.example,
          );
        });
      }
    },
    settings: .new(runs: 1, shrinkSteps: gitShrinks),
  );

  property('An example that fails to resolve for any other reason is its '
      "codebase's failure, never `Fetched`.", (Draw draw) async {
    final _Unresolvable unresolvable = draw(
      .element(_Unresolvable.values),
      label: 'unresolvable',
    );
    // Every resolution, so none is left to the draws.
    for (final Resolution resolution in Resolution.values) {
      await _onBench((_Bench bench) async {
        serveLeaf(bench.server, 'b', '1.0.0');
        bench.server.serve('a', '1.0.0', {
          'pubspec.yaml': hostedPubspec('a', '1.0.0'),
          'example/pubspec.yaml': switch (unresolvable) {
            .unserved => '${examplePubspec('a')}  unserved: ^1.0.0\n',
            .unsatisfied => '${examplePubspec('a')}  b: ^9.0.0\n',
            .missingInside =>
              '${examplePubspec('a')}  c:\n    path: ../missing\n',
            .notYaml => 'name: [a_example\n',
          },
        });
        final HostedCodebase codebase = hostedOf('a', resolution: resolution);
        await expectLater(
          bench.checkouts.lock(Hosted(codebase), bench.locks),
          throwsA(storeFault(isA<CommandFailed>())),
        );
        // A lock of its own for the example, so its checkout reaches the
        // resolve, which holds it to a lock that does not fit.
        await writeFile(
          keptLockOf(bench.locks, Hosted(codebase), .example).path,
          lockText,
        );
        await expectLater(
          bench.checkouts.checkout(Hosted(codebase), bench.locks),
          throwsA(storeFault(isA<CommandFailed>())),
        );
      });
    }
  }, settings: .new(runs: 4, shrinkSteps: gitShrinks));

  property(
    'An example is left unresolved exactly where a path dependency of it, '
    'read as pub reads it, leaves the package, and a pubspec or served '
    'overrides that pub would refuse fails its codebase.',
    (Draw draw) async {
      final String outside = draw(
        .element(['../../c', '/c', '../x/../../c']),
        label: 'outside',
      );
      final bool first = draw(.boolean(), label: 'first');
      // Every refusal, and none, under every resolution, so none is left to
      // the draws.
      for (final (_Refusal? refusal, Resolution resolution) in [
        for (final _Refusal? refusal in [null, ..._Refusal.values])
          for (final Resolution resolution in Resolution.values)
            (refusal, resolution),
      ]) {
        await _onBench((_Bench bench) async {
          bench.server.serve('a', '1.0.0', {
            'pubspec.yaml': hostedPubspec('a', '1.0.0'),
            'packages/b/pubspec.yaml': pubspecOf('b'),
            ..._refusedExample(refusal, outside, first),
          });
          final HostedCodebase codebase = hostedOf('a', resolution: resolution);
          final PackagePath example = hostedPackage(
            bench.checkout,
            codebase,
            .example,
          );
          final Matcher refused = throwsA(
            storeFault(
              isA<CommandFailed>().having(
                (CommandFailed f) => f.command.arguments,
                'arguments',
                containsAll(['pub', 'get', '--directory=${example.path}']),
              ),
            ),
          );
          final String reason = '$refusal $resolution';
          switch (refusal) {
            case null:
              expect(
                await bench.checkouts.lock(Hosted(codebase), bench.locks),
                [keptLockOf(bench.locks, Hosted(codebase), .root)],
                reason: reason,
              );
              expect(
                (await bench.checkouts.checkout(
                  Hosted(codebase),
                  bench.locks,
                )).example,
                ExampleUnresolved((dependency: .parse('c')!, path: outside)),
                reason: reason,
              );
            case _Refusal():
              await expectLater(
                bench.checkouts.lock(Hosted(codebase), bench.locks),
                refused,
                reason: reason,
              );
              // A lock of its own for the example, so its checkout reaches
              // the resolve, which pub refuses.
              await writeFile(
                keptLockOf(bench.locks, Hosted(codebase), .example).path,
                lockText,
              );
              await expectLater(
                bench.checkouts.checkout(Hosted(codebase), bench.locks),
                refused,
                reason: reason,
              );
          }
        });
      }
    },
    settings: .new(runs: 1, shrinkSteps: gitShrinks),
  );

  property('A package resolved `as-dependency` resolves where one of its own '
      'dependencies depends back on it from the host it is served from.', (
    Draw draw,
  ) async {
    final int depth = draw(.integer(min: 1, max: 3), label: 'depth');
    // Every constraint, with an example and without, so none is left to
    // the draws.
    for (final String constraint in ['any', '^1.0.0', '>=9.0.0']) {
      for (final bool example in [false, true]) {
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
            if (example) 'example/pubspec.yaml': examplePubspec('a'),
          });
          for (int n = 1; n <= depth; n++) {
            bench.server.serve('c$n', '1.0.0', {
              'pubspec.yaml': hostedPubspec(
                'c$n',
                '1.0.0',
                dependencies: n == depth
                    ? {'a': constraint}
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
              hostedPackage(bench.checkout, codebase, .root).packageConfig.path,
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
                  hostedPackage(
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
  }, settings: .new(runs: 2, shrinkSteps: gitShrinks));

  property(
    'A second checkout of a hosted codebase hands the first out untouched, '
    'unpacking and resolving nothing.',
    (Draw draw) async {
      final _Open open = draw(_open, label: 'open');
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
    settings: .new(runs: 2, shrinkSteps: gitShrinks),
  );

  property(
    'A hosted checkout whose stamp, lock or `package_config.json` differs '
    'from what was stamped is unpacked afresh.',
    (Draw draw) async {
      final _Open open = draw(_open, label: 'open');
      for (final _Shape shape in _shapesOf(open)) {
        await _onBench((_Bench bench) async {
          bench.server.serve('a', '1.0.0', _served(shape));
          final HostedCodebase codebase = hostedOf(
            'a',
            resolution: shape.resolution,
          );
          await bench.lockedCheckout(codebase);
          PackagePath of(Package package) =>
              hostedPackage(bench.checkout, codebase, package);
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
                  keptLockOf(bench.locks, Hosted(codebase), package).path,
                ).readAsString(),
                reason: '$off',
              );
            }
          }
        });
      }
    },
    settings: .new(runs: 1, shrinkSteps: gitShrinks),
  );

  property('A package and its example each resolve on their own kept lock, and a '
      'lock that is missing gives `Unlocked`, naming it.', (Draw draw) async {
    final _Open open = draw(_open, label: 'open');
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
              keptLockOf(bench.locks, Hosted(codebase), package),
          ]);
          for (final Package package in gone) {
            final File kept = .new(
              keptLockOf(bench.locks, Hosted(codebase), package).path,
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
                storeFault(
                  isA<Unlocked>().having(
                    (Unlocked u) => u.lock,
                    'lock',
                    keptLockOf(bench.locks, Hosted(codebase), lacking.first),
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
                hostedPackage(bench.checkout, codebase, package).lock.path,
              ).readAsString(),
          };
          for (final MapEntry<Package, String>(key: package, value: lock)
              in locks.entries) {
            expect(
              lock,
              await File(
                keptLockOf(bench.locks, Hosted(codebase), package).path,
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
  }, settings: .new(runs: 1, shrinkSteps: gitShrinks));

  property(
    'A hosted codebase\'s checkout takes no clone\'s claim and starts no git.',
    (Draw draw) {
      final Resolution resolution = draw(
        .element(Resolution.values),
        label: 'resolution',
      );
      final int count = draw(.integer(min: 1, max: 2), label: 'count');
      final bool again = draw(.boolean(), label: 'again');
      return _onBench((_Bench bench) async {
        for (int n = 0; n < count; n++) {
          serveLeaf(bench.server, 'p$n', '1.0.0');
          final HostedCodebase codebase = hostedOf(
            'p$n',
            name: 'app$n',
            resolution: resolution,
          );
          await bench.lockedCheckout(codebase);
          if (again) {
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
      });
    },
    settings: .new(runs: 8, shrinkSteps: gitShrinks),
  );
}

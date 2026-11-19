import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/load/loader.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/content_hash.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/parse_stamp.dart';
import 'package:muster/src/model/stamp.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:muster/src/store/runner.dart';
import 'package:muster/src/store/store_fault.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/manifests.dart';
import '../support/origin.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
import '../support/spy_runner.dart';
import '../support/tree_under.dart';
import '../support/write_file.dart';

/// How a manifest reaches a load.
enum _By {
  /// Named by the load's caller.
  argument,

  /// Listed in `MUSTER_MANIFESTS`.
  variable,
}

/// A bench for one run: two origins, a runner that keeps what it ran, and
/// the manifests a load is given.
class _Bench {
  _Bench._(this.temp, this.runner, this.origins);

  static Future<_Bench> make(Directory temp) async {
    final SpyRunner runner = .new(hermetic(temp));
    return ._(temp, runner, [
      for (final String name in ['one', 'two'])
        await .make(await .new(p.join(temp.path, name)).create(), runner),
    ]);
  }

  final Directory temp;
  final SpyRunner runner;
  final List<Origin> origins;
  final List<String> _named = [];
  final List<String> _listed = [];

  /// A codebase [name] of the origin at [origin], at a new commit holding
  /// [files], kept on a branch of its name.
  Future<GitCodebase> codebase(
    String name,
    Map<String, String> files, {
    int origin = 0,
    String root = '.',
  }) => branchedCodebase(origins[origin], name, files, root: root);

  /// Writes a manifest [stem]`.yaml` naming [codebases], given to the load
  /// [by] its caller or `MUSTER_MANIFESTS`, and returns its path.
  Future<String> manifest(
    String stem,
    List<GitCodebase> codebases,
    _By by,
  ) async {
    final String path = p.join(temp.path, 'manifests', '$stem.yaml');
    await writeManifest(path, codebases);
    give(path, by);
    return path;
  }

  /// Gives the manifest at [path] to the load [by] its caller or
  /// `MUSTER_MANIFESTS`.
  void give(String path, _By by) => switch (by) {
    .argument => _named.add(path),
    .variable => _listed.add(path),
  };

  Map<String, String> get variables => {
    if (_listed.isNotEmpty) 'MUSTER_MANIFESTS': _listed.join(':'),
  };

  Loader loader([Runner? by]) =>
      loaderIn(temp, by ?? runner, variables: variables);

  Future<Load> load([Runner? by]) => loader(by).load(named: _named);

  Future<Locking> lock([Runner? by]) => loader(by).lock(named: _named);

  String checkoutOf(GitCodebase codebase) =>
      checkoutAt(temp, codebase.name.name);
}

/// Matches an outcome that is a failure, never [Fetched].
final Matcher _failure = isA<FetchFailure>();

/// Text YAML cannot read.
const List<String> _notYaml = [
  'codebases: [',
  '{',
  '"open',
  'codebases: [1, 2',
  'a:\n  - b\n c: d',
  'codebases: {}\ncodebases: {}',
  'a: b: c',
];

/// A file name whose ending is no `.yaml`.
final Gen<String> _notYamlName = .build((Draw draw) {
  final String stem = draw(.string(alphabet: .letters, minLength: 1));
  final String ending = draw(
    .element(['', '.yml', '.YAML', '.yaml.bak', '.json', '_yaml', '.yaml~']),
  );
  return '$stem$ending';
});

/// A fault a named manifest can meet.
enum _ManifestFault { missing, unreadable, notYaml }

/// A codebase's kind, as its manifest names it.
enum _Kind { git, hosted }

/// A codebase a manifest of a draw names: the `n` that names it, whether
/// it is `good`, loading, and its `kind`.
typedef _Drawn = (int n, bool good, _Kind kind);

/// How a codebase a load hands out resolves.
enum _Handout {
  /// A git codebase, resolved at its root.
  git,

  /// A hosted package resolved `alone`.
  alone,

  /// A hosted package resolved `as-dependency`.
  asDependency,
}

/// A fault that refuses a load.
enum _Refusal {
  notManifestName,
  missing,
  unreadable,
  notYaml,
  unknownKey,
  none,
  namedTwice,
  noCache,
}

/// A codebase a load names, drawn: the [toolchain] it resolves with, and
/// whether its URL [reached] a repo, which it fails to clone where it does
/// not.
typedef _Versioned = ({Toolchain toolchain, bool reached});

/// A codebase of a load run twice, drawn: whether its package is [nested]
/// below the repo's top, holds an [example], has its locks [committed], and
/// is [listed] in a manifest `MUSTER_MANIFESTS` names, not the root's.
typedef _Repeated = ({bool nested, bool example, bool committed, bool listed});

/// A fault a codebase can meet.
enum _Fault { none, pinMissing, noRepo, unlocked, badStamp, unresolvable }

/// How a toolchain's version command ends in a test that drives it.
enum _VersionRead {
  /// It exits 0, writing the toolchain's version.
  answered,

  /// It exits 1, writing no version.
  fails,

  /// Its executable cannot start.
  unstartable,
}

/// The version command [toolchain] runs, as a [SpyRunner] gives it.
String _versionGiven(Toolchain toolchain) =>
    SpyRunner.givenOf(toolchain.version);

/// The toolchain whose version command [command] is, or null where it is
/// none's.
Toolchain? _versionOf(Command command) {
  for (final Toolchain toolchain in Toolchain.values) {
    if (_versionGiven(toolchain) == SpyRunner.givenOf(command)) {
      return toolchain;
    }
  }
  return null;
}

/// What [toolchain]'s version command writes in a test that answers it.
String _versionText(Toolchain toolchain) => switch (toolchain) {
  .dart => 'Dart SDK version: 3.13.0 (stable)',
  .flutter => '{"frameworkVersion": "3.47.9"}',
};

void main() {
  property(
    'A load reads each toolchain\'s SDK version at most once, however many '
    'codebases it names.',
    (Draw draw) => inTemp((Directory temp) async {
      final List<_Versioned> drawn = draw(
        .list(
          .build(
            (Draw draw) => (
              toolchain: draw(.element(Toolchain.values)),
              reached: draw(.boolean()),
            ),
          ),
          minLength: 1,
        ),
        label: 'drawn',
      );
      final List<_VersionRead> reads = draw(
        .list(
          .element(_VersionRead.values),
          minLength: Toolchain.values.length,
          maxLength: Toolchain.values.length,
        ),
        label: 'reads',
      );
      final _Bench bench = await .make(temp);
      bench.runner.before = (Command command) async {
        if (_versionOf(command) case final Toolchain toolchain) {
          switch (reads[toolchain.index]) {
            case .answered:
              break;
            case .fails:
              throw StoreFault(
                CommandFailed(command, 1, '', 'failed by its test'),
              );
            case .unstartable:
              throw StoreFault(Unstartable(command.executable));
          }
        }
      };
      bench.runner.answer = (Command command) => switch (_versionOf(command)) {
        final Toolchain toolchain => (
          exitCode: 0,
          stdout: _versionText(toolchain),
          stderr: '',
        ),
        null => null,
      };
      final List<GitCodebase> codebases = [];
      for (final (int i, (:toolchain, :reached)) in drawn.take(6).indexed) {
        final GitCodebase made = await bench.codebase(
          'c$i',
          packageFiles('c$i'),
        );
        // Only a Dart codebase on an answered read is resolved, since a
        // Flutter one would need Flutter's SDK, every other on an answered
        // read fails at its clone, and each on a failed read fails at it.
        codebases.add((
          name: made.name,
          url: reached && toolchain == .dart
              ? made.url
              : .parse(p.join(temp.path, 'no-repo-$i'))!,
          commit: made.commit,
          root: made.root,
          toolchain: toolchain,
        ));
      }
      await writeManifest(atRoot(temp), codebases);
      bench.runner.commands.clear();
      final Load load = await bench.load();
      expect(load, isA<Loaded>());
      for (final Toolchain toolchain in Toolchain.values) {
        expect(
          bench.runner.given.where(
            (String given) => given == _versionGiven(toolchain),
          ),
          hasLength(
            codebases.any(
                  (GitCodebase codebase) => codebase.toolchain == toolchain,
                )
                ? 1
                : 0,
          ),
          reason: toolchain.name,
        );
      }
      // A version read that failed fails each codebase of its toolchain
      // with that one failure.
      for (final GitCodebase codebase in codebases) {
        final FetchOutcome? outcome = (load as Loaded).outcomes[codebase.name];
        switch (reads[codebase.toolchain.index]) {
          case .answered:
            break;
          case .fails:
            expect(
              outcome,
              isA<CommandFailed>().having(
                (CommandFailed failed) => SpyRunner.givenOf(failed.command),
                'command',
                _versionGiven(codebase.toolchain),
              ),
              reason: codebase.name.name,
            );
          case .unstartable:
            expect(
              outcome,
              isA<Unstartable>().having(
                (Unstartable failed) => failed.executable,
                'executable',
                codebase.toolchain.executable,
              ),
              reason: codebase.name.name,
            );
        }
      }
    }),
    settings: .new(runs: 20, shrinkSteps: gitShrinks),
  );

  property(
    'A manifest whose file name does not end `.yaml` refuses the load.',
    (Draw draw) async {
      final String name = draw(_notYamlName, label: 'name');
      final _By by = draw(.element(_By.values), label: 'by');
      final int before = draw(.integer(min: 0, max: 2), label: 'before');
      expect(name, isNot(endsWith('.yaml')));
      await inTemp((Directory temp) async {
        final _Bench bench = await .make(temp);
        for (int i = 0; i < before; i++) {
          await bench.manifest('good$i', [], by);
        }
        final String path = p.join(temp.path, name);
        await writeManifest(path, []);
        bench.give(path, by);
        expect(
          await bench.load(),
          refusedFor(
            isA<NotManifestName>().having(
              (NotManifestName n) => n.path,
              'path',
              path,
            ),
          ),
        );
      });
    },
    settings: .new(runs: 40, shrinkSteps: gitShrinks),
  );

  property(
    'A named manifest that is missing, unreadable or not YAML refuses the '
    'load, naming the file and why.',
    (Draw draw) async {
      final _ManifestFault fault = draw(
        .element(_ManifestFault.values),
        label: 'fault',
      );
      final _By by = draw(.element(_By.values), label: 'by');
      final int before = draw(.integer(min: 0, max: 2), label: 'before');
      final String text = draw(.element(_notYaml), label: 'text');
      await inTemp((Directory temp) async {
        final _Bench bench = await .make(temp);
        for (int i = 0; i < before; i++) {
          await bench.manifest('good$i', [], by);
        }
        final String path = p.join(temp.path, 'faulty.yaml');
        bench.give(path, by);
        switch (fault) {
          case .missing:
            break;
          case .unreadable:
            await Directory(path).create();
          case .notYaml:
            await File(path).writeAsString(text);
        }
        expect(
          await bench.load(),
          refusedFor(switch (fault) {
            .missing => isA<ManifestMissing>().having(
              (ManifestMissing m) => m.manifest.path,
              'manifest',
              path,
            ),
            .unreadable =>
              isA<ManifestUnreadable>()
                  .having(
                    (ManifestUnreadable u) => u.manifest.path,
                    'manifest',
                    path,
                  )
                  .having(
                    (ManifestUnreadable u) => u.reason,
                    'reason',
                    isNotEmpty,
                  ),
            .notYaml =>
              isA<ManifestInvalid>()
                  .having(
                    (ManifestInvalid i) => i.manifest.path,
                    'manifest',
                    path,
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
          }),
        );
      });
    },
    settings: .new(runs: 40, shrinkSteps: gitShrinks),
  );

  property(
    'A load with no manifest at all refuses: no `muster.yaml` at the root and '
    'nothing in `MUSTER_MANIFESTS`.',
    (Draw draw) => inTemp((Directory temp) async {
      final String? listed = draw(
        .element(<String?>[null, '', ':', '::']),
        label: 'listed',
      );
      expect(
        await loaderIn(
          temp,
          .new(hermetic(temp)),
          variables: {'MUSTER_MANIFESTS': ?listed},
        ).load(),
        refusedFor(
          isA<NoManifest>().having(
            (NoManifest n) => n.root.path,
            'root',
            consumerIn(temp).path,
          ),
        ),
      );
    }),
    settings: .new(runs: 8, shrinkSteps: gitShrinks),
  );

  property(
    'A load naming git and hosted codebases gives one outcome per codebase, in '
    "the manifests' order, whatever its kind.",
    (Draw draw) => inTemp((Directory temp) async {
      final List<List<_Drawn>> manifests = draw(
        .list(
          .list(
            .build(
              (Draw draw) => (
                draw(.integer(min: 0, max: 5)),
                draw(.boolean()),
                draw(.element(_Kind.values)),
              ),
            ),
          ),
          minLength: 1,
        ),
        label: 'manifests',
      );
      final bool rootFirst = draw(.boolean(), label: 'rootFirst');
      final _Bench bench = await .make(temp);
      final PackageServer server = await .start();
      try {
        final SpyRunner pub = .new({
          ...hermetic(temp),
          ...pubVariables(temp, server),
        });
        final Set<int> seen = {};
        final Map<String, Matcher> expected = {};
        for (final (int index, List<_Drawn> codebases) in manifests.indexed) {
          final List<Entry> named = [];
          for (final (int n, bool good, _Kind kind) in codebases) {
            if (!seen.add(n)) {
              continue;
            }
            switch (kind) {
              case .git:
                final GitCodebase codebase = await bench.codebase(
                  'c$n',
                  packageFiles('c$n'),
                );
                named.add(
                  entryOf(
                    good
                        ? codebase
                        : codebaseOf(
                            bench.origins.first,
                            .parse('${n}a'.padRight(40, 'a'))!,
                            name: 'c$n',
                          ),
                  ),
                );
                expected['c$n'] = good
                    ? fetchedAt(bench.checkoutOf(codebase))
                    : isA<PinMissing>();
              case .hosted:
                serveLeaf(server, 'h$n', '1.0.0');
                // A version no host serves fails its unpack.
                named.add(
                  hostedEntryOf(
                    hostedOf(
                      'h$n',
                      name: 'c$n',
                      version: good ? '1.0.0' : '9.9.9',
                    ),
                  ),
                );
                expected['c$n'] = good
                    ? fetchedAt('${checkoutAt(temp, 'c$n')}/h$n-1.0.0')
                    : isA<CommandFailed>();
            }
          }
          if (index == 0 && rootFirst) {
            await writeFile(atRoot(temp), renderManifest(named));
          } else {
            final String path = p.join(temp.path, 'manifests', 'm$index.yaml');
            await writeFile(path, renderManifest(named));
            bench.give(path, rootFirst ? .variable : .argument);
          }
        }
        // Every hosted codebase loads on a kept lock, which a lock writes.
        await bench.lock(pub);
        expect(await bench.load(pub), loadedWith(expected));
      } finally {
        await server.close();
      }
    }),
    settings: .new(runs: 10, shrinkSteps: gitShrinks),
  );

  property(
    'The package config a `Fetched` names is the one its codebase\'s '
    'resolve wrote, whatever its resolution.',
    (Draw draw) => inTemp((Directory temp) async {
      final bool example = draw(.boolean(), label: 'example');
      final _Bench bench = await .make(temp);
      final PackageServer server = await .start();
      try {
        final SpyRunner pub = .new({
          ...hermetic(temp),
          ...pubVariables(temp, server),
        });
        serveLeaf(server, 'h', '1.0.0', example: example);
        // Every resolution in one manifest, so none is left to the draws.
        final List<Entry> entries = [
          for (final _Handout handout in _Handout.values)
            switch (handout) {
              .git => entryOf(
                await bench.codebase(
                  'c${handout.index}',
                  packageFiles('c${handout.index}'),
                ),
              ),
              .alone => hostedEntryOf(hostedOf('h', name: 'c${handout.index}')),
              .asDependency => hostedEntryOf(
                hostedOf(
                  'h',
                  name: 'c${handout.index}',
                  resolution: .asDependency,
                ),
              ),
            },
        ];
        await writeFile(atRoot(temp), renderManifest(entries));
        await bench.lock(pub);
        final Load load = await bench.load(pub);
        for (final _Handout handout in _Handout.values) {
          final CodebaseName name = .parse('c${handout.index}')!;
          final Stamp stamp = parseStamp(
            await File(CheckoutPath.of(consumerIn(temp), name).stamp.path)
                .readAsString(),
          )!;
          switch (load) {
            case Loaded(:final Map<CodebaseName, FetchOutcome> outcomes):
              switch (outcomes[name]) {
                case Fetched(:final PackagePath package):
                  expect(
                    ContentHash.of(
                      await File(package.packageConfig.path).readAsBytes(),
                    ),
                    stamp.packages[Package.root]!.packageConfig,
                    reason: handout.name,
                  );
                case final FetchOutcome? other:
                  fail('${handout.name}: $other');
              }
            case Refused():
              fail('$load');
          }
        }
      } finally {
        await server.close();
      }
    }),
    settings: .new(runs: 3, shrinkSteps: gitShrinks),
  );

  property('A refused load starts no process and writes no file.', (
    Draw draw,
  ) async {
    final _Refusal refusal = draw(.element(_Refusal.values), label: 'refusal');
    final int before = draw(.integer(min: 0, max: 2), label: 'before');
    await inTemp((Directory temp) async {
      final _Bench bench = await .make(temp);
      // A load with no manifest at all is given none, good or faulty.
      final List<GitCodebase> good = [
        for (
          int i = 0;
          i <
              switch (refusal) {
                .none => 0,
                .notManifestName ||
                .missing ||
                .unreadable ||
                .notYaml ||
                .unknownKey ||
                .namedTwice ||
                .noCache => before,
              };
          i++
        )
          await bench.codebase('g$i', packageFiles('g$i')),
      ];
      for (final (int i, GitCodebase codebase) in good.indexed) {
        await bench.manifest('good$i', [codebase], .variable);
      }
      final String faulty = p.join(temp.path, 'faulty.yaml');
      switch (refusal) {
        case .notManifestName:
          await writeManifest(p.join(temp.path, 'faulty.yml'), []);
          bench.give(p.join(temp.path, 'faulty.yml'), .variable);
        case .missing:
          bench.give(faulty, .variable);
        case .unreadable:
          await Directory(faulty).create();
          bench.give(faulty, .variable);
        case .notYaml:
          await File(faulty).writeAsString(_notYaml.first);
          bench.give(faulty, .variable);
        case .unknownKey:
          await File(faulty)
              .writeAsString(renderManifest([], top: [('depth', '1')]));
          bench.give(faulty, .variable);
        case .none:
          break;
        case .namedTwice:
          final GitCodebase twice = await bench.codebase(
            'twice',
            packageFiles('twice'),
          );
          await bench.manifest('first', [twice], .variable);
          await bench.manifest('second', [twice], .variable);
        case .noCache:
          await bench.manifest('cached', [
            await bench.codebase('cached', packageFiles('cached')),
          ], .variable);
      }
      final Loader loader = switch (refusal) {
        .noCache => loaderIn(
          temp,
          bench.runner,
          variables: bench.variables,
          cached: false,
        ),
        .notManifestName ||
        .missing ||
        .unreadable ||
        .notYaml ||
        .unknownKey ||
        .none ||
        .namedTwice => bench.loader(),
      };
      final Map<String, String> tree = await treeUnder(temp.path);
      bench.runner.commands.clear();
      expect(await loader.load(), isA<Refused>());
      expect(bench.runner.given, isEmpty);
      expect(await treeUnder(temp.path), tree);
    });
  }, settings: .new(runs: 24, shrinkSteps: gitShrinks));

  property(
    'A load right after another load hands out the same paths, and clones, '
    'checks out and resolves nothing.',
    (Draw draw) => inTemp((Directory temp) async {
      final List<_Repeated> draws = draw(
        .list(
          .build(
            (Draw draw) => (
              nested: draw(.boolean()),
              example: draw(.boolean()),
              committed: draw(.boolean()),
              listed: draw(.boolean()),
            ),
          ),
          minLength: 1,
        ),
        label: 'draws',
      );
      final _Bench bench = await .make(temp);
      final List<GitCodebase> atRootManifest = [];
      final List<GitCodebase> inListed = [];
      final String listed = p.join(temp.path, 'listed.yaml');
      for (final (int i, drawn) in draws.take(3).indexed) {
        final String at = drawn.nested ? 'pkg' : '.';
        final GitCodebase codebase = await bench.codebase('c$i', {
          ...packageFiles('c$i', at: at, locked: drawn.committed),
          if (drawn.example)
            ...packageFiles(
              'c${i}_example',
              at: '$at/example',
              locked: drawn.committed,
            ),
        }, root: at);
        (drawn.listed ? inListed : atRootManifest).add(codebase);
        if (!drawn.committed) {
          for (final Package package in [.root, if (drawn.example) .example]) {
            final KeptLockPath kept = keptLockOf(
              locksBeside(drawn.listed ? listed : atRoot(temp)),
              Git(codebase),
              package,
            );
            await writeFile(kept.path, lockText);
          }
        }
      }
      await writeManifest(atRoot(temp), atRootManifest);
      await writeManifest(listed, inListed);
      bench.give(listed, .variable);
      final Load first = await bench.load();
      expect(first, isA<Loaded>());
      final Map<CodebaseName, FetchOutcome> handed = (first as Loaded).outcomes;
      expect(handed.values, everyElement(isA<Fetched>()));
      bench.runner.commands.clear();
      final Load second = await bench.load();
      expect(
        second,
        loadedWith({
          for (final MapEntry<CodebaseName, FetchOutcome>(:key, :value)
              in handed.entries)
            key.name: fetchedAt((value as Fetched).package.path),
        }),
      );
      expect(
        bench.runner.given,
        everyElement(anyOf(endsWith(' --version'), contains(' status '))),
      );
    }),
    settings: .new(runs: 10, shrinkSteps: gitShrinks),
  );

  property(
    'Every failure a codebase meets comes back as an outcome other than '
    '`Fetched`, and nothing throws out of `Loader.load` but a bug.',
    (Draw draw) => inTemp((Directory temp) async {
      final List<_Fault> faults = draw(
        .list(.element(_Fault.values), minLength: 1),
        label: 'faults',
      );
      final bool unstartable = draw(
        .integer(min: 0, max: 3).map((int n) => n == 0),
        label: 'unstartable',
      );
      final _Bench bench = await .make(temp);
      final List<GitCodebase> codebases = [];
      final Map<String, Matcher> expected = {};
      for (final (int i, _Fault fault) in faults.take(4).indexed) {
        final String name = 'c$i';
        final GitCodebase made = await bench.codebase(name, switch (fault) {
          .unlocked => packageFiles(name, locked: false),
          .unresolvable => {
            'pubspec.yaml':
                '${pubspecOf(name)}dependencies:\n  gone:\n    path: ../gone\n',
            'pubspec.lock': lockText,
          },
          .none || .pinMissing || .noRepo || .badStamp => packageFiles(name),
        });
        codebases.add(switch (fault) {
          .pinMissing => codebaseOf(
            bench.origins.first,
            .parse('f' * 40)!,
            name: name,
          ),
          .noRepo => (
            name: made.name,
            url: .parse(p.join(temp.path, 'no-repo-$i'))!,
            commit: made.commit,
            root: made.root,
            toolchain: made.toolchain,
          ),
          .none || .unlocked || .badStamp || .unresolvable => made,
        });
        switch (fault) {
          case .badStamp:
            await Directory('${bench.checkoutOf(made)}.stamp')
                .create(recursive: true);
          case .none || .pinMissing || .noRepo || .unlocked || .unresolvable:
            break;
        }
        expected[name] = unstartable
            ? isA<Unstartable>()
            : switch (fault) {
                .none => isA<Fetched>(),
                .pinMissing => isA<PinMissing>(),
                .noRepo => isA<CommandFailed>().having(
                  (CommandFailed f) => f.command.executable,
                  'executable',
                  Executable.git,
                ),
                .unlocked => isA<Unlocked>(),
                .badStamp => isA<StoreFailed>(),
                .unresolvable => isA<CommandFailed>().having(
                  (CommandFailed f) => f.command.executable,
                  'executable',
                  Executable.dart,
                ),
              };
      }
      await writeManifest(atRoot(temp), codebases);
      final Load load = await bench.load(
        unstartable ? unstartableIn(temp) : null,
      );
      expect(load, loadedWith(expected));
      for (final (int i, _Fault fault) in faults.take(4).indexed) {
        if (unstartable ||
            switch (fault) {
              .none => false,
              .pinMissing ||
              .noRepo ||
              .unlocked ||
              .badStamp ||
              .unresolvable => true,
            }) {
          expect(
            (load as Loaded).outcomes[CodebaseName.parse('c$i')!],
            _failure,
          );
        }
      }
    }),
    settings: .new(runs: 12, shrinkSteps: gitShrinks),
  );

  property(
    'A checkout or a clone deleted by hand comes back on the next load.',
    (Draw draw) async {
      final List<bool> fromSecond = draw(
        .list(.boolean(), minLength: 1),
        label: 'fromSecond',
      );
      final Set<int> checkouts = draw(
        .set(.integer(min: 0, max: 2)),
        label: 'checkouts',
      );
      final Set<int> clones = draw(
        .set(.integer(min: 0, max: 1)),
        label: 'clones',
      );
      await inTemp((Directory temp) async {
        final _Bench bench = await .make(temp);
        final List<GitCodebase> codebases = [
          for (final (int i, bool second) in fromSecond.take(3).indexed)
            await bench.codebase(
              'c$i',
              packageFiles('c$i'),
              origin: second ? 1 : 0,
            ),
        ];
        await writeManifest(atRoot(temp), codebases);
        final Map<String, Matcher> handed = {
          for (final GitCodebase codebase in codebases)
            codebase.name.name: fetchedAt(bench.checkoutOf(codebase)),
        };
        expect(await bench.load(), loadedWith(handed));
        for (final (int i, GitCodebase codebase) in codebases.indexed) {
          if (checkouts.contains(i)) {
            await Directory(bench.checkoutOf(codebase)).delete(recursive: true);
          }
        }
        for (final int origin in clones) {
          final Directory clone = .new(
            cloneOf(
              temp,
              codebaseOf(bench.origins[origin], codebases.first.commit),
            ).path,
          );
          if (await clone.exists()) {
            await clone.delete(recursive: true);
          }
        }
        expect(await bench.load(), loadedWith(handed));
        for (final GitCodebase codebase in codebases) {
          expect(
            await File(p.join(bench.checkoutOf(codebase), 'pubspec.yaml'))
                .readAsString(),
            pubspecOf(codebase.name.name),
          );
          expect(
            await Directory(cloneOf(temp, codebase).path).exists(),
            isTrue,
          );
        }
      });
    },
    settings: .new(runs: 10, shrinkSteps: gitShrinks),
  );
}

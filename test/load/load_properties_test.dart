import 'dart:io';

import 'package:glados/glados.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/load/loader.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;

import '../support/git.dart';
import '../support/loads.dart';
import '../support/manifests.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/shrinking_at_most.dart';
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

/// A bench for one draw: two origins, a runner that keeps what it ran, and
/// the manifests a load is given.
class _Bench {
  _Bench._(this.temp, this.runner, this.origins);

  static Future<_Bench> make(Directory temp) async {
    final SpyRunner runner = .new(hermetic(temp));
    return ._(temp, runner, [
      for (final String name in ['one', 'two'])
        await .make(await Directory(p.join(temp.path, name)).create(), runner),
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
  }) async {
    final Origin at = origins[origin];
    final Commit pin = await at.commit(null, files);
    await at.ref('refs/heads/$name', pin);
    return codebaseOf(at, pin, name: name, root: root);
  }

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
final Generator<String> _notYamlName = any
    .combine2(
      any.nonEmptyLetters,
      any.choose([
        '',
        '.yml',
        '.YAML',
        '.yaml.bak',
        '.json',
        '_yaml',
        '.yaml~',
      ]),
      (String stem, String ending) => '$stem$ending',
    )
    .shrinkingAtMost(gitTries);

/// A fault a named manifest can meet.
enum _ManifestFault { missing, unreadable, notYaml }

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

/// A fault a codebase can meet.
enum _Fault { none, pinMissing, noRepo, unlocked, badStamp, unresolvable }

/// The version command [toolchain] runs, as a [SpyRunner] gives it.
String _versionGiven(Toolchain toolchain) =>
    '${toolchain.executable.name} ${toolchain.version.arguments.join(' ')}';

/// What each toolchain's version command writes in a test that answers it.
const Map<Toolchain, String> _versionText = {
  .dart: 'Dart SDK version: 3.13.0 (stable)',
  .flutter: '{"frameworkVersion": "3.47.9"}',
};

void main() {
  Glados(
    any
        .nonEmptyList(
          any.combine2(
            any.choose(Toolchain.values),
            any.bool,
            (Toolchain toolchain, bool reached) =>
                (toolchain: toolchain, reached: reached),
          ),
        )
        .shrinkingAtMost(gitTries),
    .new(numRuns: 15),
  ).test(
    'A load reads each toolchain\'s SDK version at most once, however many '
    'codebases it names.',
    (List<({Toolchain toolchain, bool reached})> drawn) =>
        inTemp((Directory temp) async {
          final _Bench bench = await .make(temp);
          bench.runner.answer = (Command command) {
            for (final MapEntry<Toolchain, String>(:key, :value)
                in _versionText.entries) {
              if (_versionGiven(key) ==
                  '${command.executable.name} '
                      '${command.arguments.join(' ')}') {
                return (exitCode: 0, stdout: value, stderr: '');
              }
            }
            return null;
          };
          final List<GitCodebase> codebases = [];
          for (final (int i, (:toolchain, :reached)) in drawn.take(6).indexed) {
            final GitCodebase made = await bench.codebase(
              'c$i',
              packageFiles('c$i'),
            );
            // Only a Dart codebase is resolved, since a Flutter one would
            // need Flutter's SDK, and every other fails at its clone.
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
          expect(await bench.load(), isA<Loaded>());
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
        }),
  );

  Glados3(
    _notYamlName,
    any.choose(_By.values).shrinkingAtMost(gitTries),
    any.intInRange(0, 3).shrinkingAtMost(gitTries),
    .new(numRuns: 40),
  ).test('A manifest whose file name does not end `.yaml` refuses the load.', (
    String name,
    _By by,
    int before,
  ) async {
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
  });

  Glados3(
    any.choose(_ManifestFault.values).shrinkingAtMost(gitTries),
    any.choose(_By.values).shrinkingAtMost(gitTries),
    any
        .combine2(
          any.intInRange(0, 3),
          any.choose(_notYaml),
          (int before, String text) => (before, text),
        )
        .shrinkingAtMost(gitTries),
    .new(numRuns: 40),
  ).test('A named manifest that is missing, unreadable or not YAML refuses the '
      'load, naming the file and why.', (
    _ManifestFault fault,
    _By by,
    (int, String) draw,
  ) async {
    final (int before, String text) = draw;
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
  });

  Glados(
    any.choose([null, '', ':', '::']).shrinkingAtMost(gitTries),
    .new(numRuns: 8),
  ).test(
    'A load with no manifest at all refuses: no `muster.yaml` at the root and '
    'nothing in `MUSTER_MANIFESTS`.',
    (String? listed) => inTemp((Directory temp) async {
      expect(
        await loaderIn(
          temp,
          .new(hermetic(temp)),
          variables: {'MUSTER_MANIFESTS': ?listed},
        ).load(),
        refusedFor(isA<NoManifest>()),
      );
    }),
  );

  Glados2(
    any
        .nonEmptyList(
          any.list(
            any.combine2(
              any.intInRange(0, 6),
              any.bool,
              (int n, bool good) => (n, good),
            ),
          ),
        )
        .shrinkingAtMost(gitTries),
    any.bool.shrinkingAtMost(gitTries),
    .new(numRuns: 10),
  ).test(
    "Every codebase the manifests name gets exactly one outcome, in the "
    "manifests' order, keyed by its name.",
    (List<List<(int, bool)>> manifests, bool rootFirst) =>
        inTemp((Directory temp) async {
          final _Bench bench = await .make(temp);
          final Set<int> seen = {};
          final Map<String, Matcher> expected = {};
          for (final (int index, List<(int, bool)> codebases)
              in manifests.indexed) {
            final List<GitCodebase> named = [];
            for (final (int n, bool good) in codebases) {
              if (!seen.add(n)) {
                continue;
              }
              final GitCodebase codebase = await bench.codebase(
                'c$n',
                packageFiles('c$n'),
              );
              named.add(
                good
                    ? codebase
                    : codebaseOf(
                        bench.origins.first,
                        .parse('${n}a'.padRight(40, 'a'))!,
                        name: 'c$n',
                      ),
              );
              expected['c$n'] = good
                  ? fetchedAt(bench.checkoutOf(codebase))
                  : isA<PinMissing>();
            }
            if (index == 0 && rootFirst) {
              await writeManifest(atRoot(temp), named);
            } else {
              await bench.manifest(
                'm$index',
                named,
                rootFirst ? .variable : .argument,
              );
            }
          }
          expect(await bench.load(), loadedWith(expected));
        }),
  );

  Glados2(
    any.choose(_Refusal.values).shrinkingAtMost(gitTries),
    any.intInRange(0, 3).shrinkingAtMost(gitTries),
    .new(numRuns: 24),
  ).test('A refused load starts no process and writes no file.', (
    _Refusal refusal,
    int before,
  ) async {
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
  });

  Glados(
    any
        .nonEmptyList(
          any.combine4(
            any.bool,
            any.bool,
            any.bool,
            any.bool,
            (bool nested, bool example, bool committed, bool listed) => (
              nested: nested,
              example: example,
              committed: committed,
              listed: listed,
            ),
          ),
        )
        .shrinkingAtMost(gitTries),
    .new(numRuns: 10),
  ).test(
    'A load right after another load hands out the same paths, and clones, '
    'checks out and resolves nothing.',
    (
      List<({bool nested, bool example, bool committed, bool listed})> draws,
    ) => inTemp((Directory temp) async {
      final _Bench bench = await .make(temp);
      final List<GitCodebase> atRootManifest = [];
      final List<GitCodebase> inListed = [];
      final String listed = p.join(temp.path, 'listed.yaml');
      for (final (int i, draw) in draws.take(3).indexed) {
        final String at = draw.nested ? 'pkg' : '.';
        final GitCodebase codebase = await bench.codebase('c$i', {
          ...packageFiles('c$i', at: at, locked: draw.committed),
          if (draw.example)
            ...packageFiles(
              'c${i}_example',
              at: '$at/example',
              locked: draw.committed,
            ),
        }, root: at);
        (draw.listed ? inListed : atRootManifest).add(codebase);
        if (!draw.committed) {
          for (final Package package in [.root, if (draw.example) .example]) {
            final KeptLockPath kept = .of(
              locksBeside(draw.listed ? listed : atRoot(temp)),
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
  );

  Glados2(
    any.nonEmptyList(any.choose(_Fault.values)).shrinkingAtMost(gitTries),
    any.intInRange(0, 4).map((int n) => n == 0).shrinkingAtMost(gitTries),
    .new(numRuns: 12),
  ).test(
    'Every failure a codebase meets comes back as an outcome other than '
    '`Fetched`, and nothing throws out of `Muster.load` but a bug.',
    (List<_Fault> faults, bool unstartable) => inTemp((Directory temp) async {
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
  );

  Glados3(
    any.nonEmptyList(any.bool).shrinkingAtMost(gitTries),
    any.set(any.intInRange(0, 3)).shrinkingAtMost(gitTries),
    any.set(any.intInRange(0, 2)).shrinkingAtMost(gitTries),
    .new(numRuns: 10),
  ).test('A checkout or a clone deleted by hand comes back on the next load.', (
    List<bool> fromSecond,
    Set<int> checkouts,
    Set<int> clones,
  ) async {
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
        expect(await Directory(cloneOf(temp, codebase).path).exists(), isTrue);
      }
    });
  });
}

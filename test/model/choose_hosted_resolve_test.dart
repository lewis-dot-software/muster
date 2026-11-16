import 'package:muster/src/model/choose_hosted_resolve.dart';
import 'package:muster/src/model/hosted_resolve.dart';
import 'package:muster/src/model/os.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/package_name.dart';
import 'package:test/test.dart';

import '../support/lines_printed.dart';

void main() {
  final PackageName a = .parse('a')!;

  /// What a hosted codebase of the package `a` does with its [package],
  /// whose pubspec is [pubspec] beside the [served] overrides, on [os].
  HostedResolve choose(
    Package package,
    String? pubspec, {
    String? served,
    Os os = .posix,
  }) => chooseHostedResolve(
    package,
    pubspec: pubspec,
    served: served,
    host: a,
    os: os,
  );

  /// An example's pubspec, its [section] holding [entry] by [name].
  String pubspecWith(String section, String name, String entry) =>
      'name: a_example\n$section:\n  $name:\n$entry';

  /// The example left unresolved for the path dependency on [name] at
  /// [path].
  LeftUnresolved outside(String name, String path) =>
      LeftUnresolved((dependency: .parse(name)!, path: path));

  /// An example resolved, its pubspec neither a member nor overriding.
  const Resolves plain = Resolves((member: false, overrides: false));

  group('the root', () {
    test('resolves whether or not it holds its pubspec', () {
      expect(choose(.root, 'name: a\n'), plain);
      expect(choose(.root, null), plain);
    });

    test(
      'resolves whatever its pubspec holds, a path that leaves among it',
      () {
        expect(
          choose(.root, pubspecWith('dependencies', 'b', '    path: ../b\n')),
          plain,
        );
      },
    );

    test('reads a member for a pubspec of `resolution: workspace` alone', () {
      expect(
        choose(.root, 'name: a\nresolution: workspace\n'),
        const Resolves((member: true, overrides: false)),
      );
      expect(choose(.root, 'name: a\nresolution: external\n'), plain);
    });

    test('reads overrides for a pubspec holding `dependency_overrides`, empty '
        'or not', () {
      for (final String overrides in [
        'dependency_overrides:\n  b:\n    path: ../b\n',
        'dependency_overrides:\n',
      ]) {
        expect(
          choose(.root, 'name: a\n$overrides'),
          const Resolves((member: false, overrides: true)),
          reason: overrides,
        );
      }
    });

    test('reads neither from a pubspec that is no YAML map', () {
      for (final String pubspec in [
        'name: [a\n',
        '- workspace\n',
        '',
        '!!%a',
        '!!%ab',
        '%YAML 1.99999999999999999999\n---\nname: a\n',
      ]) {
        expect(choose(.root, pubspec), plain, reason: pubspec);
      }
    });
  });

  group('the example', () {
    test('is not held where the package holds no pubspec for it', () {
      expect(choose(.example, null), const NotHeld());
      expect(
        choose(.example, null, served: 'dependency_overrides:\n'),
        const NotHeld(),
      );
    });

    test('resolves where no path leaves, its pubspec read as the root\'s', () {
      expect(choose(.example, 'name: a_example\n'), plain);
      expect(
        choose(
          .example,
          'name: a_example\nresolution: workspace\n'
          'dependencies:\n  a:\n    path: ..\n',
        ),
        const Resolves((member: true, overrides: false)),
      );
    });

    test('is left unresolved for a path dependency outside the package, in '
        'any section that stands', () {
      for (final String section in ['dependencies', 'dev_dependencies']) {
        expect(
          choose(.example, pubspecWith(section, 'b', '    path: ../../b\n')),
          outside('b', '../../b'),
          reason: section,
        );
      }
      // The pubspec's own overrides stand where served overrides hold none.
      expect(
        choose(
          .example,
          pubspecWith('dependency_overrides', 'b', '    path: ../../b\n'),
          served: 'resolution:\n',
        ),
        outside('b', '../../b'),
      );
    });

    test('is left unresolved for a path that is absolute, or climbs above the '
        'top, in the paths of the system pub runs on', () {
      for (final (Os os, String path) in [
        (.posix, '/b'),
        (.posix, '../..'),
        (.posix, '../x/../../b'),
        (.windows, r'C:\b'),
        (.windows, '/b'),
        (.windows, r'..\..\b'),
        (.windows, '../../b'),
      ]) {
        expect(
          choose(
            .example,
            pubspecWith('dependencies', 'b', '    path: ${_yaml(path)}\n'),
            os: os,
          ),
          outside('b', path),
          reason: '$os $path',
        );
      }
    });

    test("resolves for a path that climbs only by another system's "
        'separator, which pub reads as a name inside the package', () {
      for (final String path in [r'..\..\b', r'C:\b']) {
        expect(
          choose(
            .example,
            pubspecWith('dependencies', 'b', '    path: ${_yaml(path)}\n'),
          ),
          plain,
          reason: path,
        );
      }
    });

    test('reads an override with no value as standing, the host serving it at '
        'any version', () {
      expect(
        choose(
          .example,
          'name: a_example\n'
          'dependencies:\n  a:\n    path: ..\n  b:\n    path: ../../b\n',
          served: 'dependency_overrides:\n  b:\n',
        ),
        plain,
      );
    });

    test('reads served overrides empty of YAML as holding none, as pub does, '
        "so the pubspec's own stand", () {
      for (final String served in ['', '# nothing\n', '\n\n']) {
        expect(
          choose(
            .example,
            pubspecWith('dependencies', 'b', '    path: ../../b\n'),
            served: served,
          ),
          outside('b', '../../b'),
          reason: served,
        );
      }
    });

    test('resolves for a path inside the package, its top among it', () {
      for (final String path in [
        '..',
        '../',
        '../packages/b',
        'b',
        '.',
        '../x/..',
      ]) {
        expect(
          choose(
            .example,
            pubspecWith('dependencies', 'b', '    path: ${_yaml(path)}\n'),
          ),
          plain,
          reason: path,
        );
      }
    });

    test('resolves for a dependency by any other source', () {
      for (final String entry in [
        '    ^1.0.0\n',
        '    hosted: https://pub.example\n    version: ^1.0.0\n',
        '    git:\n      url: https://example.com/b.git\n      path: ../../b\n',
        '    sdk: flutter\n',
      ]) {
        expect(
          choose(
            .example,
            pubspecWith('dependencies', 'b', entry.replaceFirst('    ^', '^')),
          ),
          plain,
          reason: entry,
        );
      }
    });

    test("resolves for the package itself where no overrides are served, "
        "since muster's override points it at the package's top", () {
      expect(
        choose(
          .example,
          pubspecWith('dependencies', 'a', '    path: ../../a\n'),
        ),
        plain,
      );
    });

    test("reads the pubspec's own overrides as replaced by muster's where no "
        'overrides are served', () {
      expect(
        choose(
          .example,
          'name: a_example\n'
          'dependencies:\n  b: ^1.0.0\n'
          'dependency_overrides:\n  b:\n    path: ../../b\n',
        ),
        const Resolves((member: false, overrides: true)),
      );
    });

    test("reads served overrides in place of the pubspec's own where they "
        "hold `dependency_overrides`, and the pubspec's where they do not", () {
      const String pubspec =
          'name: a_example\n'
          'dependencies:\n  a:\n    path: ../../a\n  b: ^1.0.0\n'
          'dependency_overrides:\n  a:\n    path: ..\n';
      expect(
        choose(
          .example,
          pubspec,
          served: 'dependency_overrides:\n  b:\n    path: ../../b\n',
        ),
        outside('a', '../../a'),
      );
      expect(
        choose(
          .example,
          pubspec,
          served:
              'dependency_overrides:\n  a:\n    path: ..\n'
              '  b:\n    path: ../../b\n',
        ),
        outside('b', '../../b'),
      );
      expect(
        choose(.example, pubspec, served: 'resolution:\n'),
        const Resolves((member: false, overrides: true)),
      );
      expect(
        choose(
          .example,
          'name: a_example\ndependencies:\n  a:\n    path: ../../a\n',
          served: 'resolution:\n',
        ),
        outside('a', '../../a'),
      );
    });

    test('is left unresolved for a package listed in both sections, by a '
        'path that leaves in either, as pub reads both', () {
      for (final (String dependencies, String dev) in [
        ('../../c', '../packages/c'),
        ('../packages/c', '../../c'),
      ]) {
        expect(
          choose(
            .example,
            'name: a_example\n'
            'dependencies:\n  c:\n    path: $dependencies\n'
            'dev_dependencies:\n  c:\n    path: $dev\n',
          ),
          outside('c', '../../c'),
          reason: '$dependencies $dev',
        );
      }
      // An override replaces both.
      expect(
        choose(
          .example,
          'name: a_example\n'
          'dependencies:\n  c:\n    path: ../../c\n'
          'dev_dependencies:\n  c:\n    path: ../../c\n',
          served: 'dependency_overrides:\n  c:\n    path: ../packages/c\n',
        ),
        plain,
      );
    });

    test("is left unresolved for the first in its pubspec's order", () {
      expect(
        choose(
          .example,
          'name: a_example\n'
          'dependencies:\n  c:\n    path: ../../c\n  b:\n    path: ../../b\n',
        ),
        outside('c', '../../c'),
      );
    });

    test('is left unresolved beside entries pub reads past, since only its '
        'resolve fails on them', () {
      for (final (String entry, String? served) in [
        ('  b:\n    path: ../packages/b\n    version: ^1.0.0\n', null),
        ('  b:\n    path: ../packages/b\n    version:\n', null),
        ('  b:\n', null),
        ('  b: {}\n', null),
        ('  b:\n    version: ^1.0.0\n', null),
        ('  b:\n    foo: bar\n', null),
        ('  b:\n    sdk: flutterx\n', null),
        // The pubspec's own overrides, which pub reads in neither case.
        ('dependency_overrides: 3\n', null),
        ('dependency_overrides: 3\n', 'dependency_overrides:\n'),
      ]) {
        expect(
          choose(
            .example,
            'name: a_example\n'
            'dependencies:\n'
            '  c:\n    path: ../../c\n'
            '$entry',
            served: served,
          ),
          outside('c', '../../c'),
          reason: entry,
        );
      }
    });

    test('resolves where pub refuses the pubspec, even beside a path that '
        'leaves, so its own resolve fails the codebase', () {
      const String leaving = 'dependencies:\n  c:\n    path: ../../c\n';
      for (final String pubspec in [
        'name: [a_example\n',
        '- a_example\n',
        '',
        '# comments alone\n',
        leaving,
        'name: 3\n$leaving',
        'name: My-App\n$leaving',
        'name: class\n$leaving',
        'name: a_example\ndependencies: 3\n',
        'name: a_example\ndependencies:\n  - c\n',
        'name: a_example\n${leaving}dev_dependencies: 3\n',
        'name: a_example\n${leaving}dependency_overrides:\n  - c\n',
      ]) {
        expect(
          choose(
            .example,
            pubspec,
            served: pubspec.contains('dependency_overrides') ? '' : null,
          ),
          isA<Resolves>(),
          reason: pubspec,
        );
      }
    });

    test('resolves where pub refuses an entry, before or after the path that '
        'leaves, so its own resolve fails the codebase', () {
      for (final String entry in [
        '  my-b: any\n',
        '  3: any\n',
        '  null: any\n',
        '  a_example:\n    path: .\n',
        '  b: 3\n',
        '  b: [x]\n',
        '  b: notaversion\n',
        '  b:\n    version: 3\n',
        '  b:\n    version: notaversion\n',
        '  b:\n    path: ../packages/b\n    version: notaversion\n',
        '  b:\n    path: ../packages/b\n    git: https://example.com/b.git\n',
        '  b:\n    version: ^1.0.0\n    path: ../b\n    hosted: x\n',
        '  b:\n    3: x\n',
        '  b:\n    path: 3\n',
        '  b:\n    path:\n',
        '  b:\n    sdk: 3\n',
      ]) {
        for (final bool first in [true, false]) {
          const String leaving = '  c:\n    path: ../../c\n';
          expect(
            choose(
              .example,
              'name: a_example\ndependencies:\n'
              '${first ? '$entry$leaving' : '$leaving$entry'}',
            ),
            plain,
            reason: '$entry first: $first',
          );
        }
      }
    });

    test('resolves for a dependency named by a word pub reserves for a '
        "package's name, which no package can bear, so its resolve fails", () {
      expect(
        choose(
          .example,
          'name: a_example\ndependencies:\n'
          '  class:\n    path: ../packages/b\n  c:\n    path: ../../c\n',
        ),
        plain,
      );
    });

    test('resolves where pub refuses the served overrides, even beside a path '
        'that leaves, so its own resolve fails the codebase', () {
      for (final String served in [
        'dependency_overrides: [c\n',
        '- c\n',
        'c\n',
        '3\n',
        'foo: 1\n',
        'dependency_overrides: 3\n',
        'dependency_overrides:\n  my-c: any\n',
        'dependency_overrides:\n  a_example:\n    path: .\n',
        'dependency_overrides:\n  c:\n    path: 3\n',
        // A leaving path in the served overrides themselves.
        'foo: 1\ndependency_overrides:\n  c:\n    path: ../../c\n',
        'dependency_overrides:\n  c:\n    path: ../../c\n  my-b: any\n',
      ]) {
        for (final String pubspec in [
          pubspecWith('dependencies', 'c', '    path: ../../c\n'),
          pubspecWith('dependencies', 'c', '    ^1.0.0\n'),
        ]) {
          expect(
            choose(.example, pubspec, served: served),
            plain,
            reason: '$served beside $pubspec',
          );
        }
      }
    });

    test('resolves where the pubspec is no YAML map, whatever leaving path '
        'served overrides hold', () {
      for (final String pubspec in [
        'name: [a_example\n',
        '- a_example\n',
        'name: a_example\ndependencies: 3\n',
      ]) {
        expect(
          choose(
            .example,
            pubspec,
            served: 'dependency_overrides:\n  b:\n    path: ../../b\n',
          ),
          plain,
          reason: pubspec,
        );
      }
    });

    test(
      'reads past a directive the YAML reader warns of, printing nothing',
      () {
        late final HostedResolve chosen;
        expect(
          linesPrinted(
            () => chosen = choose(
              .example,
              '%FOO bar\n---\n'
              '${pubspecWith('dependencies', 'b', '    path: ../../b\n')}',
              served: '%FOO bar\n---\nresolution:\n',
            ),
          ),
          isEmpty,
        );
        expect(chosen, outside('b', '../../b'));
        late final HostedResolve root;
        expect(
          linesPrinted(
            () => root = choose(
              .root,
              '%FOO bar\n---\nname: a\nresolution: workspace\n',
            ),
          ),
          isEmpty,
        );
        expect(root, const Resolves((member: true, overrides: false)));
      },
    );
  });
}

/// [text] as a YAML string.
String _yaml(String text) => '"${text.replaceAll(r'\', r'\\')}"';

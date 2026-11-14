import 'package:muster/src/model/example_path_outside.dart';
import 'package:muster/src/model/os.dart';
import 'package:muster/src/model/outside_path.dart';
import 'package:muster/src/model/package_name.dart';
import 'package:test/test.dart';

import '../support/lines_printed.dart';

void main() {
  final PackageName a = .parse('a')!;

  /// An example's pubspec, its [section] holding [entry] by [name].
  String pubspecWith(String section, String name, String entry) =>
      'name: a_example\n$section:\n  $name:\n$entry';

  /// The path dependency on [name] at [path], as [examplePathOutside] names
  /// it.
  OutsidePath outside(String name, String path) =>
      (dependency: .parse(name)!, path: path);

  test('names a path dependency outside the package, in any section that '
      'stands', () {
    for (final String section in ['dependencies', 'dev_dependencies']) {
      expect(
        examplePathOutside(
          pubspecWith(section, 'b', '    path: ../../b\n'),
          null,
          a,
          .posix,
        ),
        outside('b', '../../b'),
        reason: section,
      );
    }
    // The pubspec's own overrides stand where served overrides hold none.
    expect(
      examplePathOutside(
        pubspecWith('dependency_overrides', 'b', '    path: ../../b\n'),
        'resolution:\n',
        a,
        .posix,
      ),
      outside('b', '../../b'),
    );
  });

  test('names a path that is absolute, or climbs above the top, in the '
      "paths of the system pub runs on", () {
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
        examplePathOutside(
          pubspecWith('dependencies', 'b', '    path: ${_yaml(path)}\n'),
          null,
          a,
          os,
        ),
        outside('b', path),
        reason: '$os $path',
      );
    }
  });

  test("names nothing for a path that climbs only by another system's "
      'separator, which pub reads as a name inside the package', () {
    for (final String path in [r'..\..\b', r'C:\b']) {
      expect(
        examplePathOutside(
          pubspecWith('dependencies', 'b', '    path: ${_yaml(path)}\n'),
          null,
          a,
          .posix,
        ),
        isNull,
        reason: path,
      );
    }
  });

  test('reads an override with no value as standing, the host serving it at '
      'any version', () {
    expect(
      examplePathOutside(
        'name: a_example\n'
            'dependencies:\n  a:\n    path: ..\n  b:\n    path: ../../b\n',
        'dependency_overrides:\n  b:\n',
        a,
        .posix,
      ),
      isNull,
    );
  });

  test('reads served overrides empty of YAML as holding none, as pub does, '
      "so the pubspec's own stand", () {
    for (final String served in ['', '# nothing\n', '\n\n']) {
      expect(
        examplePathOutside(
          pubspecWith('dependencies', 'b', '    path: ../../b\n'),
          served,
          a,
          .posix,
        ),
        outside('b', '../../b'),
        reason: served,
      );
    }
  });

  test('names nothing where the served overrides are no YAML map, since pub '
      'refuses them', () {
    for (final String served in [
      'dependency_overrides: [b\n',
      '- b\n',
      'b\n',
    ]) {
      expect(
        examplePathOutside(
          pubspecWith('dependencies', 'b', '    path: ../../b\n'),
          served,
          a,
          .posix,
        ),
        isNull,
        reason: served,
      );
    }
  });

  test('names nothing for a path inside the package, its top among it', () {
    for (final String path in [
      '..',
      '../',
      '../packages/b',
      'b',
      '.',
      '../x/..',
    ]) {
      expect(
        examplePathOutside(
          pubspecWith('dependencies', 'b', '    path: ${_yaml(path)}\n'),
          null,
          a,
          .posix,
        ),
        isNull,
        reason: path,
      );
    }
  });

  test('names nothing for a dependency by any other source', () {
    for (final String entry in [
      '    ^1.0.0\n',
      '    hosted: https://pub.example\n    version: ^1.0.0\n',
      '    git:\n      url: https://example.com/b.git\n      path: ../../b\n',
      '    sdk: flutter\n',
    ]) {
      expect(
        examplePathOutside(
          pubspecWith('dependencies', 'b', entry.replaceFirst('    ^', '^')),
          null,
          a,
          .posix,
        ),
        isNull,
        reason: entry,
      );
    }
  });

  test("names nothing for the package itself where no overrides are served, "
      "since muster's override points it at the package's top", () {
    expect(
      examplePathOutside(
        pubspecWith('dependencies', 'a', '    path: ../../a\n'),
        null,
        a,
        .posix,
      ),
      isNull,
    );
  });

  test("reads the pubspec's own overrides as replaced by muster's where no "
      'overrides are served', () {
    expect(
      examplePathOutside(
        'name: a_example\n'
        'dependencies:\n  b: ^1.0.0\n'
        'dependency_overrides:\n  b:\n    path: ../../b\n',
        null,
        a,
        .posix,
      ),
      isNull,
    );
  });

  test('reads served overrides in place of the pubspec\'s own where they '
      'hold `dependency_overrides`, and the pubspec\'s where they do not', () {
    const String pubspec =
        'name: a_example\n'
        'dependencies:\n  a:\n    path: ../../a\n  b: ^1.0.0\n'
        'dependency_overrides:\n  a:\n    path: ..\n';
    expect(
      examplePathOutside(
        pubspec,
        'dependency_overrides:\n  b:\n    path: ../../b\n',
        a,
        .posix,
      ),
      outside('a', '../../a'),
    );
    expect(
      examplePathOutside(
        pubspec,
        'dependency_overrides:\n  a:\n    path: ..\n  b:\n    path: ../../b\n',
        a,
        .posix,
      ),
      outside('b', '../../b'),
    );
    expect(examplePathOutside(pubspec, 'resolution:\n', a, .posix), isNull);
    expect(
      examplePathOutside(
        'name: a_example\ndependencies:\n  a:\n    path: ../../a\n',
        'resolution:\n',
        a,
        .posix,
      ),
      outside('a', '../../a'),
    );
  });

  test('names the first in its pubspec\'s order', () {
    expect(
      examplePathOutside(
        'name: a_example\n'
        'dependencies:\n  c:\n    path: ../../c\n  b:\n    path: ../../b\n',
        null,
        a,
        .posix,
      ),
      outside('c', '../../c'),
    );
  });

  test('names nothing where pub would refuse the pubspec or the entry', () {
    for (final String pubspec in [
      'name: [a\n',
      '- a\n',
      '',
      'name: a_example\ndependencies:\n  my-b:\n    path: ../../b\n',
      'name: a_example\ndependencies:\n  b:\n    path: 3\n',
      'name: a_example\ndependencies: 3\n',
    ]) {
      expect(
        examplePathOutside(pubspec, null, a, .posix),
        isNull,
        reason: pubspec,
      );
    }
  });

  test('reads past a directive the YAML reader warns of, printing nothing', () {
    late final OutsidePath? named;
    expect(
      linesPrinted(
        () => named = examplePathOutside(
          '%FOO bar\n---\n${pubspecWith('dependencies', 'b', '    path: ../../b\n')}',
          '%FOO bar\n---\nresolution:\n',
          a,
          .posix,
        ),
      ),
      isEmpty,
    );
    expect(named, outside('b', '../../b'));
  });
}

/// [text] as a YAML string.
String _yaml(String text) => '"${text.replaceAll(r'\', r'\\')}"';

import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/manifest.dart';
import 'package:muster/src/model/manifest_parse.dart';
import 'package:muster/src/model/manifest_refusal.dart';
import 'package:muster/src/model/parse_manifest.dart';
import 'package:muster/src/model/wanted.dart';
import 'package:muster/src/model/written.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/lines_printed.dart';
import '../support/manifests.dart';
import '../support/refusals.dart';

final String _sha1 = 'ab' * 20;
final String _sha256 = 'cd' * 32;

/// The text of a manifest of one codebase, `app`, its fields [fields].
String _one(Map<String, String> fields) => renderManifest([
  ('app', [for (final MapEntry(:key, :value) in fields.entries) (key, value)]),
]);

/// The fields of a git codebase that stands, with [change] laid over them and
/// each key in [drop] left out.
Map<String, String> _fields({
  Map<String, String> change = const {},
  Set<String> drop = const {},
}) => {
  'git': 'https://example.com/app.git',
  'commit': _sha1,
  'root': 'pkgs/app',
  'toolchain': 'flutter',
  ...change,
}..removeWhere((String key, String _) => drop.contains(key));

/// The fields of a hosted codebase that stands, with [change] laid over them
/// and each key in [drop] left out.
Map<String, String> _hostedFields({
  Map<String, String> change = const {},
  Set<String> drop = const {},
}) => {
  'hosted': 'args',
  'version': '2.7.0',
  'resolution': 'alone',
  'toolchain': 'dart',
  ...change,
}..removeWhere((String key, String _) => drop.contains(key));

void main() {
  test('a manifest that stands comes back as its codebases, in its order', () {
    final ManifestParse parse = parseManifest('''
codebases:
  zed:
    git: /srv/zed.git
    commit: $_sha256
    toolchain: dart
  app:
    git: https://example.com/app.git
    commit: $_sha1
    root: ./pkgs//app/
    toolchain: flutter
  analyzer:
    hosted: analyzer
    version: 007.1.0-dev.01+02
    resolution: as-dependency
    toolchain: dart
''');

    expect(
      parse,
      isA<ManifestParsed>().having((p) => p.manifest.codebases, 'codebases', [
        Git(codebase('zed', '/srv/zed.git', _sha256, '.', .dart)),
        Git(
          codebase(
            'app',
            'https://example.com/app.git',
            _sha1,
            'pkgs/app',
            .flutter,
          ),
        ),
        Hosted(
          hosted('analyzer', 'analyzer', '7.1.0-dev.1+2', .asDependency, .dart),
        ),
      ]),
    );
  });

  test('a plain value YAML types as a number or a bool is read as written', () {
    final String digits = '12' * 20;
    expect(
      parseManifest(
        'codebases:\n'
        '  app:\n    git: /srv/a.git\n    commit: $digits\n'
        '    root: 1\n    toolchain: dart\n'
        '  bench:\n    git: /srv/b.git\n    commit: $digits\n'
        '    root: true\n    toolchain: dart',
      ),
      isA<ManifestParsed>().having((p) => p.manifest.codebases, 'codebases', [
        Git(codebase('app', '/srv/a.git', digits, '1', .dart)),
        Git(codebase('bench', '/srv/b.git', digits, 'true', .dart)),
      ]),
    );
  });

  test('a manifest with no codebases comes back empty', () {
    expect(
      parseManifest('codebases: {}'),
      isA<ManifestParsed>().having(
        (p) => p.manifest.codebases,
        'codebases',
        isEmpty,
      ),
    );
  });

  group('text that is no YAML document refuses:', () {
    for (final (String what, String text) in [
      ('broken syntax', 'codebases: {'),
      ('two documents', 'codebases: {}\n---\ncodebases: {}'),
      ('a key twice', 'codebases: {}\ncodebases: {}'),
    ]) {
      test(what, () {
        expect(
          parseManifest(text),
          refused(
            isA<NotYaml>().having((r) => r.reason, 'reason', contains('line')),
          ),
        );
      });
    }
  });

  test('a tag whose escape does not decode, and a `%YAML` version past an '
      "integer's range, refuse", () {
    for (final String text in [
      '!!%a',
      '!!%ab',
      '%YAML 1.99999999999999999999\n---\ncodebases: {}',
    ]) {
      expect(
        parseManifest(text),
        refused(
          isA<NotYaml>().having(
            (r) => r.reason,
            'reason',
            contains('does not read'),
          ),
        ),
        reason: text,
      );
    }
  });

  group('a key muster does not know refuses, named by its path:', () {
    test('at the top', () {
      expect(
        parseManifest(renderManifest([], top: [('codebase', 'x')])),
        unknownKey(['codebase']),
      );
    });

    test('in a codebase', () {
      expect(
        parseManifest(_one(_fields(change: {'depth': '1'}))),
        unknownKey(['codebases', 'app', 'depth']),
      );
    });

    for (final String key in ['hosted', 'version', 'resolution']) {
      test('a hosted codebase\'s `$key` in a git codebase', () {
        expect(
          parseManifest(_one(_fields(change: {key: 'x'}))),
          unknownKey(['codebases', 'app', key]),
        );
      });
    }

    for (final String key in ['git', 'commit', 'root']) {
      test('a git codebase\'s `$key` in a hosted codebase', () {
        expect(
          parseManifest(_one(_hostedFields(change: {key: 'x'}))),
          unknownKey(['codebases', 'app', key]),
        );
      });
    }

    test(
      'a key of the other kind\'s, after the first key of a kind\'s own',
      () {
        expect(
          parseManifest(
            _one({
              'toolchain': 'dart',
              'version': '1.0.0',
              'git': '/srv/a.git',
            }),
          ),
          unknownKey(['codebases', 'app', 'git']),
        );
      },
    );

    test('a key that is no string, as the manifest writes it', () {
      expect(parseManifest('codebases: {}\n1: x'), unknownKey(['1']));
      expect(parseManifest('codebases: {}\nTrue: x'), unknownKey(['True']));
    });

    test('an empty key at the top, apart from the top itself', () {
      expect(parseManifest('codebases: {}\n"": x'), unknownKey(['']));
    });

    test('a key holding a dot, apart from the keys either side of it', () {
      expect(
        parseManifest(_one(_fields(change: {'a.b': 'x'}))),
        unknownKey(['codebases', 'app', 'a.b']),
      );
    });
  });

  group('a key a manifest must hold, left out, refuses:', () {
    test('`codebases`', () {
      expect(parseManifest('{}'), missingKey(['codebases']));
    });

    for (final String key in ['git', 'commit', 'toolchain']) {
      test('`$key`', () {
        expect(
          parseManifest(_one(_fields(drop: {key}))),
          missingKey(['codebases', 'app', key]),
        );
      });
    }

    for (final String key in ['hosted', 'version', 'toolchain']) {
      test('a hosted codebase\'s `$key`', () {
        expect(
          parseManifest(_one(_hostedFields(drop: {key}))),
          missingKey(['codebases', 'app', key]),
        );
      });
    }
  });

  group('a codebase of neither kind refuses, named by its path:', () {
    for (final (String what, String text) in [
      ('one of no keys', 'codebases:\n  app: {}'),
      ('one of a toolchain alone', 'codebases:\n  app:\n    toolchain: dart'),
    ]) {
      test(what, () {
        expect(
          parseManifest(text),
          refused(
            isA<MissingKind>().having(
              (MissingKind r) => r.path,
              'path',
              pathOf(['codebases', 'app']),
            ),
          ),
        );
      });
    }
  });

  for (final String package in [
    '_fe_analyzer_shared',
    '_discoveryapis_commons',
    'Args',
    'async',
    'a.b_c',
    'class.x',
  ]) {
    test('a hosted package named "$package"', () {
      expect(
        parseManifest(_one(_hostedFields(change: {'hosted': package}))),
        isA<ManifestParsed>().having(
          (p) => p.manifest.codebases.single,
          'codebase',
          Hosted(hosted('app', package, '2.7.0', .alone, .dart)),
        ),
      );
    });
  }

  test('every word pub lets stand names a hosted package, and every word it '
      'reserves, in any case, refuses', () {
    for (final String word in pubLetStand) {
      expect(
        parseManifest(_one(_hostedFields(change: {'hosted': word}))),
        isA<ManifestParsed>(),
        reason: word,
      );
    }
    for (final String word in pubReserved) {
      for (final String spelt in [word, word.toUpperCase()]) {
        expect(
          parseManifest(_one(_hostedFields(change: {'hosted': spelt}))),
          badValue(['codebases', 'app', 'hosted'], .packageName),
          reason: spelt,
        );
      }
    }
  });

  test('a resolution left out is alone', () {
    expect(
      parseManifest(_one(_hostedFields(drop: {'resolution'}))),
      isA<ManifestParsed>().having(
        (p) => p.manifest.codebases.single,
        'codebase',
        Hosted(hosted('app', 'args', '2.7.0', .alone, .dart)),
      ),
    );
  });

  test('a root left out is the repo\'s top', () {
    expect(
      parseManifest(_one(_fields(drop: {'root'}))),
      isA<ManifestParsed>().having(
        (p) => switch (p.manifest.codebases.single) {
          Git(:final GitCodebase codebase) => codebase.root.path,
          Hosted() => null,
        },
        'root',
        '.',
      ),
    );
  });

  group('a value its key cannot take refuses, named by its path:', () {
    for (final (String what, String text, List<String> keys) in [
      ('an empty manifest', '', []),
      ('a top that is a list', '- codebases', []),
      ('`codebases` left empty', 'codebases:', ['codebases']),
      ('`codebases` as a list', 'codebases: []', ['codebases']),
      ('a codebase left empty', 'codebases:\n  app:', ['codebases', 'app']),
      ('a codebase as a string', 'codebases:\n  app: x', ['codebases', 'app']),
    ]) {
      test(what, () {
        expect(parseManifest(text), badValue(keys, .mapping));
      });
    }

    for (final (String key, String value, Wanted wanted) in [
      ('git', '', .gitUrl),
      ('git', '--upload-pack=touch /tmp/x', .gitUrl),
      ('git', '/srv/a.git\n', .gitUrl),
      ('git', '/srv/a.git\r\n/srv/b.git', .gitUrl),
      ('git', '/srv/a\u2028b.git', .gitUrl),
      ('git', '/srv/a\x00b.git', .gitUrl),
      ('commit', 'main', .fullHash),
      ('commit', 'abcdef1', .fullHash),
      ('commit', 'AB' * 20, .fullHash),
      ('commit', '${'a' * 40}\n', .fullHash),
      ('commit', 'a' * 41, .fullHash),
      ('toolchain', 'Dart', .toolchain),
      ('toolchain', 'go', .toolchain),
      ('root', '..', .rootInsideRepo),
      ('root', 'pkgs/../..', .rootInsideRepo),
      ('root', '/abs', .rootInsideRepo),
      ('root', 'C:/pkgs', .rootInsideRepo),
      ('root', r'..\pkgs', .rootInsideRepo),
      ('root', 'pkgs/app\n', .rootInsideRepo),
      ('root', 'pkgs\r\napp', .rootInsideRepo),
      ('root', 'pkgs/a\u2028pp', .rootInsideRepo),
      ('root', 'pkgs/a\x00pp', .rootInsideRepo),
    ]) {
      test('`$key` of ${value.isEmpty ? 'nothing' : '"$value"'}', () {
        expect(
          parseManifest(_one(_fields(change: {key: value}))),
          badValue(['codebases', 'app', key], wanted),
        );
      });
    }

    for (final (String key, String value, Wanted wanted) in [
      ('hosted', 'my-args', .packageName),
      ('hosted', '9args', .packageName),
      ('hosted', 'class', .packageName),
      ('hosted', 'Class', .packageName),
      ('hosted', 'AWAIT', .packageName),
      ('hosted', '.args', .packageName),
      ('hosted', 'args.', .packageName),
      ('hosted', 'a..b', .packageName),
      ('hosted', 'a.9b', .packageName),
      ('hosted', '', .packageName),
      ('version', '2.7', .version),
      ('version', '^2.7.0', .version),
      ('version', 'v2.7.0', .version),
      ('version', '2.7.0-', .version),
      ('version', 'any', .version),
      ('version', '${'9' * 20}.0.0', .version),
      ('resolution', 'dependency', .resolution),
      ('resolution', 'as_dependency', .resolution),
      ('resolution', 'Alone', .resolution),
      ('toolchain', 'go', .toolchain),
    ]) {
      test('a hosted codebase\'s `$key` of "$value"', () {
        expect(
          parseManifest(_one(_hostedFields(change: {key: value}))),
          badValue(['codebases', 'app', key], wanted),
        );
      });
    }

    test('the value as the manifest writes it', () {
      expect(
        parseManifest(
          'codebases:\n  app:\n    git: /srv/a.git\n    commit: $_sha1\n'
          '    toolchain: go',
        ),
        refused(
          isA<BadValue>().having(
            (r) => r.written,
            'written',
            isA<WrittenText>().having((w) => w.text, 'text', 'go'),
          ),
        ),
      );
    });

    test('a git URL written as a block over lines', () {
      expect(
        parseManifest(
          'codebases:\n  app:\n    git: |\n      /srv/a.git\n      /srv/b.git\n'
          '    commit: $_sha1\n    toolchain: dart',
        ),
        badValue(['codebases', 'app', 'git'], .gitUrl),
      );
    });

    test('a root written as a block, its line break kept', () {
      expect(
        parseManifest(
          'codebases:\n  app:\n    git: /srv/a.git\n    commit: $_sha1\n'
          '    root: |\n      packages/app\n    toolchain: dart',
        ),
        badValue(['codebases', 'app', 'root'], .rootInsideRepo),
      );
    });

    test('a root left empty', () {
      expect(
        parseManifest(
          'codebases:\n  app:\n    git: /srv/a.git\n    commit: $_sha1\n'
          '    root:\n    toolchain: dart',
        ),
        badValue(['codebases', 'app', 'root'], .rootInsideRepo),
      );
    });

    test('a value that is no string', () {
      expect(
        parseManifest(
          'codebases:\n  app:\n    git: [x]\n    commit: $_sha1\n'
          '    toolchain: dart',
        ),
        badValue(['codebases', 'app', 'git'], .gitUrl),
      );
    });

    for (final String name in ['App', '1app', '_app', 'my-app', '']) {
      test('a codebase named "$name"', () {
        expect(
          parseManifest(renderManifest([(name, [])])),
          badValue(['codebases', name], .codebaseName),
        );
      });
    }
  });

  group('a directive the YAML reader warns of is passed over, printing '
      'nothing:', () {
    for (final String directive in ['%FOO bar', '%YAML 1.3']) {
      test(directive, () {
        final String manifest = _one(_fields());
        late final ManifestParse parse;
        expect(
          linesPrinted(
            () => parse = parseManifest('$directive\n---\n$manifest'),
          ),
          isEmpty,
        );
        expect(
          parse,
          isA<ManifestParsed>().having(
            (ManifestParsed p) => p.manifest.codebases,
            'codebases',
            switch (parseManifest(manifest)) {
              ManifestParsed(:final Manifest manifest) => manifest.codebases,
              final ManifestRefused refused => fail('refused $refused'),
            },
          ),
        );
      });
    }
  });

  test("a warning callback the caller set stands after a parse, and hears "
      "none of the parse's warnings, whether it parses or refuses", () {
    final YamlWarningCallback before = yamlWarningCallback;
    addTearDown(() => yamlWarningCallback = before);
    final List<String> heard = [];
    void hear(String message, [Object? _]) => heard.add(message);
    yamlWarningCallback = hear;
    expect(
      parseManifest('%FOO\n---\n${_one(_fields())}'),
      isA<ManifestParsed>(),
    );
    expect(parseManifest('%FOO\n---\ncodebases: [x'), isA<ManifestRefused>());
    expect(heard, isEmpty);
    expect(yamlWarningCallback, same(hear));
  });
}

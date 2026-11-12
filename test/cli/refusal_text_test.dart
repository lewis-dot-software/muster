import 'package:muster/muster.dart';
import 'package:muster/src/cli/refusal_text.dart';
import 'package:muster/src/model/manifest_parse.dart';
import 'package:muster/src/model/parse_manifest.dart';
import 'package:test/test.dart';

import '../support/outcomes.dart';

/// What each refusal's line names, so a person can act on it.
List<String> _named(LoadRefusal refusal) => switch (refusal) {
  NoManifest() => ['muster.yaml', 'MUSTER_MANIFESTS'],
  NotManifestName(:final String path) => [path, '.yaml'],
  ManifestMissing(:final manifest) => [manifest.path],
  ManifestUnreadable(:final manifest, :final String reason) => [
    manifest.path,
    reason,
  ],
  ManifestInvalid(:final manifest, :final refusal) => [
    manifest.path,
    ...switch (refusal) {
      NotYaml(:final String reason) => [reason],
      UnknownKey(:final path) || MissingKey(:final path) => [path.dotted],
      BadValue(:final path, :final Written written) => [
        path.dotted,
        _writtenNamed(written),
      ],
    },
  ],
  CodebaseNamedTwice(:final name, :final first, :final second) => [
    name.name,
    first.path,
    second.path,
  ],
  NoWorkingDirectory(:final String reason) => [reason],
  NoCache(:final Os os) => [
    'MUSTER_CACHE',
    ...switch (os) {
      .posix => ['XDG_CACHE_HOME', 'HOME'],
      .windows => ['LOCALAPPDATA'],
    },
  ],
};

/// What a refusal's line calls [written].
String _writtenNamed(Written written) => switch (written) {
  WrittenText(:final String text) => text,
  WrittenList() => 'a list',
  WrittenMapping() => 'a mapping',
  WrittenNothing() => 'an empty value',
};

/// The line a manifest at `/consumer/muster.yaml` holding [text] refuses
/// with.
String _refusalOf(String text) => switch (parseManifest(text)) {
  ManifestRefused(:final ManifestRefusal refusal) => refusalText(
    ManifestInvalid(.parse('/consumer/muster.yaml', .posix)!, refusal),
  ),
  ManifestParsed() => fail('$text parsed'),
};

final String _sha1 = 'ab' * 20;

void main() {
  for (final LoadRefusal refusal in everyRefusal) {
    test('a refusal of ${refusal.runtimeType} is one line naming what to '
        'act on', () {
      final String text = refusalText(refusal);
      expect(text, isNot(contains('\n')));
      for (final String named in _named(refusal)) {
        expect(text, contains(named));
      }
    });
  }

  group('a manifest refuses in one line naming its cause:', () {
    final Map<String, (String, String)> cases = {
      'an empty one': ('', 'an empty value is not a mapping'),
      'one of comments alone': (
        '# none yet\n',
        'an empty value is not a mapping',
      ),
      "one of YAML's null word alone": ('~\n', '~ is not a mapping'),
      'one whose top is a list': ('- a\n- b\n', 'a list is not a mapping'),
      'one that is not YAML, at where it stopped, with none of its source': (
        'codebases: [',
        'not YAML: line 1, column 13: Expected node content.',
      ),
      'a block value, as the kind of value it is': (
        'codebases:\n  app:\n    git:\n      - a\n      - b\n',
        'codebases.app.git: a list is not a git URL',
      ),
      'a mapping value, as the kind of value it is': (
        'codebases:\n  app:\n    git:\n      a: b\n',
        'codebases.app.git: a mapping is not a git URL',
      ),
      'a key left with no value': (
        'codebases:\n  app:\n    git: /srv/a.git\n    commit: $_sha1\n'
            '    toolchain:\n',
        'codebases.app.toolchain: an empty value is not dart or flutter',
      ),
      'a value over lines, quoted with its breaks escaped': (
        'codebases:\n  app:\n    git: /srv/a.git\n    commit: $_sha1\n'
            '    toolchain: |\n      dart\n',
        r'codebases.app.toolchain: "|\n      dart" is not dart or flutter',
      ),
      "a key holding Unicode's line breaks or a delete, quoted with each "
          'escaped': (
        r'"a\Nb\Lc\Pd\x7fe": f'
            '\n',
        r'"a\u0085b\u2028c\u2029d\u007fe": a key muster does not know',
      ),
      'a key holding another control character, quoted with it escaped': (
        r'"a\x07b\x9fc": d'
            '\n',
        r'"a\u0007b\u009fc": a key muster does not know',
      ),
      'a key holding a tab, as it stands': (
        r'"a\tb": c'
            '\n',
        'a\tb: a key muster does not know',
      ),
      'a key holding a line break, quoted with it escaped': (
        '"a\\nb": c\n',
        r'"a\nb": a key muster does not know',
      ),
    };
    for (final MapEntry(key: String name, value: (String text, String line))
        in cases.entries) {
      test(name, () {
        expect(_refusalOf(text), '/consumer/muster.yaml: $line');
      });
    }
  });

  test('a path or a reason holding a line break is quoted with its breaks '
      'escaped', () {
    final ManifestPath broken = .parse('/consumer/a\nb.yaml', .posix)!;
    final ManifestPath plain = .parse('/consumer/c.yaml', .posix)!;
    expect(
      [
        refusalText(const NotManifestName('/consumer/a\nb.yml')),
        refusalText(ManifestMissing(broken)),
        refusalText(ManifestUnreadable(plain, 'Permission\ndenied')),
        refusalText(ManifestInvalid(plain, const NotYaml('line 1\nline 2'))),
        refusalText(
          CodebaseNamedTwice(.parse('app')!, first: broken, second: plain),
        ),
        refusalText(const NoWorkingDirectory('gone\r')),
      ],
      [
        r'"/consumer/a\nb.yml": a manifest'
            "'"
            r's file name ends .yaml',
        r'"/consumer/a\nb.yaml": no such manifest',
        r'/consumer/c.yaml: "Permission\ndenied"',
        r'/consumer/c.yaml: not YAML: "line 1\nline 2"',
        r'app: named in "/consumer/a\nb.yaml" and again in /consumer/c.yaml',
        r'no working directory: "gone\r"',
      ],
    );
  });

  test('no cache names the variables of its system alone', () {
    expect(
      refusalText(const NoCache(.posix)),
      'no cache: none of MUSTER_CACHE, XDG_CACHE_HOME as an absolute path, '
      'or HOME is set',
    );
    expect(
      refusalText(const NoCache(.windows)),
      'no cache: neither MUSTER_CACHE nor LOCALAPPDATA is set',
    );
  });
}

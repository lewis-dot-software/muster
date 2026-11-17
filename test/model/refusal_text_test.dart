import 'package:muster/muster.dart';
import 'package:muster/src/model/manifest_parse.dart';
import 'package:muster/src/model/parse_manifest.dart';
import 'package:test/test.dart';

import '../support/manifest_refusal_case.dart';
import '../support/refusal_case.dart';

/// What each refusal's line names, so a person can act on it.
List<Pattern> _named(LoadRefusal refusal) => switch (refusal) {
  NoManifest() => ['muster.yaml', 'MUSTER_MANIFESTS'],
  NotManifestName(:final String path) => [path, '.yaml'],
  ManifestMissing(:final manifest) => [manifest.path],
  ManifestUnreadable(:final manifest, :final String reason) => [
    manifest.path,
    reason,
  ],
  ManifestInvalid(:final manifest, :final refusal) => [
    manifest.path,
    ..._manifestNamed(refusal),
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
      .posix => ['XDG_CACHE_HOME', RegExp(r'\bHOME\b')],
      .windows => ['LOCALAPPDATA'],
    },
  ],
  NoClaim(:final String system) => [system],
};

/// What a manifest refusal's line names, so a person can act on it.
List<Pattern> _manifestNamed(ManifestRefusal refusal) => switch (refusal) {
  NotYaml(:final String reason) => [reason],
  UnknownKey(:final path) ||
  MissingKey(:final path) ||
  MissingKind(:final path) => [path.dotted],
  BadValue(:final path, :final Written written) => [
    path.dotted,
    _writtenNamed(written),
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
  ManifestRefused(:final ManifestRefusal refusal) => ManifestInvalid(
    .parse('/consumer/muster.yaml', .posix)!,
    refusal,
  ).toString(),
  ManifestParsed() => fail('$text parsed'),
};

final String _sha1 = 'ab' * 20;

/// A case of a manifest that refuses: its `text`, and the `line` its
/// refusal gives after the manifest's path.
typedef _Case = (String text, String line);

void main() {
  for (final LoadRefusal refusal in RefusalCase.every) {
    final String text = '$refusal';
    test('a refusal of ${refusal.runtimeType}, $text, is one line naming '
        'what to act on', () {
      expect(text, isNot(contains('\n')));
      for (final Pattern named in _named(refusal)) {
        expect(text, contains(named));
      }
    });
  }

  for (final ManifestRefusalCase refusalCase in ManifestRefusalCase.values) {
    for (final ManifestRefusal refusal in refusalCase.samples) {
      final String text = '$refusal';
      test('a manifest refusal of ${refusal.runtimeType}, $text, is one line '
          'naming what to act on', () {
        expect(text, isNot(contains('\n')));
        for (final Pattern named in _manifestNamed(refusal)) {
          expect(text, contains(named));
        }
      });
    }
  }

  group('a manifest refuses in one line naming its cause:', () {
    final Map<String, _Case> cases = {
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
      'a codebase of neither kind': (
        'codebases:\n  app:\n    toolchain: dart\n',
        'codebases.app: neither git nor hosted',
      ),
      'a codebase name pub takes but muster does not': (
        'codebases:\n  _app:\n    hosted: args\n    version: 2.7.0\n'
            '    toolchain: dart\n',
        'codebases._app: _app is not a name of lowercase letters, digits and '
            'underscores, opening on a letter',
      ),
      'a package name pub refuses': (
        'codebases:\n  app:\n    hosted: class\n    version: 2.7.0\n'
            '    toolchain: dart\n',
        'codebases.app.hosted: class is not a pub package name',
      ),
      'a version pub cannot read': (
        'codebases:\n  app:\n    hosted: args\n    version: ^2.7.0\n'
            '    toolchain: dart\n',
        'codebases.app.version: ^2.7.0 is not a version pub reads',
      ),
      'a resolution of neither word': (
        'codebases:\n  app:\n    hosted: args\n    version: 2.7.0\n'
            '    resolution: dependency\n    toolchain: dart\n',
        'codebases.app.resolution: dependency is not alone or as-dependency',
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
      'a key below the top holding a line break, quoted apart from the keys '
          'before it': (
        'codebases:\n  app:\n    toolchain: dart\n    "a\\nb": x\n',
        r'codebases.app."a\nb": a key muster does not know',
      ),
      'a block key, as written with none of the break its block ends on': (
        'codebases: {}\n? - a\n  - b\n: x\n',
        r'"- a\n  - b": a key muster does not know',
      ),
      'an empty key at the top, quoted': (
        'codebases: {}\n"": x\n',
        '"": a key muster does not know',
      ),
      'a key holding a dot, quoted apart from the keys either side': (
        'codebases:\n  app:\n    toolchain: dart\n    a.b: x\n',
        'codebases.app."a.b": a key muster does not know',
      ),
      'a codebase named with a dot, quoted': (
        'codebases:\n  a.b: {}\n',
        'codebases."a.b": a.b is not a name of lowercase letters, digits and '
            'underscores, opening on a letter',
      ),
      'a key opening on a quote, quoted with it escaped': (
        'codebases: {}\n\'"a\': x\n',
        r'"\"a": a key muster does not know',
      ),
      'a key that is no string, as the manifest writes it': (
        'codebases: {}\nTrue: x\n',
        'True: a key muster does not know',
      ),
      'a git URL written as a block over lines, quoted with its breaks '
          'escaped': (
        'codebases:\n  app:\n    git: |\n      /srv/a.git\n      /srv/b.git\n'
            '    commit: $_sha1\n    toolchain: dart\n',
        r'codebases.app.git: "|\n      /srv/a.git\n      /srv/b.git" is not '
            'a git URL',
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
        const NotManifestName('/consumer/a\nb.yml').toString(),
        ManifestMissing(broken).toString(),
        ManifestUnreadable(plain, 'Permission\ndenied').toString(),
        ManifestInvalid(plain, const NotYaml('line 1\nline 2')).toString(),
        CodebaseNamedTwice(
          .parse('app')!,
          first: broken,
          second: plain,
        ).toString(),
        const NoWorkingDirectory('gone\r').toString(),
        const NoClaim('free\nbsd').toString(),
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
        r'no claim: muster knows no C library to lock a claim with on '
            r'"free\nbsd"',
      ],
    );
  });

  test('no cache names the variables of its system alone', () {
    expect(
      const NoCache(.posix).toString(),
      'no cache: none of MUSTER_CACHE, XDG_CACHE_HOME as an absolute path, '
      'or HOME is set',
    );
    expect(
      const NoCache(.windows).toString(),
      'no cache: neither MUSTER_CACHE nor LOCALAPPDATA is set',
    );
  });

  test('no claim names the system', () {
    expect(
      const NoClaim('freebsd').toString(),
      'no claim: muster knows no C library to lock a claim with on freebsd',
    );
  });
}

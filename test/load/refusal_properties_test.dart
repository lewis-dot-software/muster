import 'dart:convert';
import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/cache_directory.dart';
import 'package:muster/src/model/cache_variable.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/loads.dart';
import '../support/manifest_refusal_case.dart';
import '../support/manifests.dart';
import '../support/refusal_case.dart';
import '../support/spy_runner.dart';
import '../support/written_case.dart';

final String _sha1 = 'ab' * 20;

/// Lines a manifest is drawn from: its keys at each depth, values of each
/// kind and of none, block values, keys and values over lines, and text
/// that is not YAML.
final List<String> _lines = [
  'codebases:',
  '  app:',
  '    git: /srv/a.git',
  '    commit: $_sha1',
  '    toolchain: dart',
  '    toolchain: go',
  '    root:',
  '    git:',
  '    git: |',
  '      a',
  '      - b',
  '    depth: 1',
  '  "a\\nb":',
  '  ? [a, b]',
  '  : {}',
  '"x\\ry": 1',
  '- a',
  '? |',
  '  key',
  ': value',
  '# a comment',
  '',
  '{',
  'codebases: [',
  '\t- a',
];

/// The characters drawn text is made of, YAML's indicators and line breaks
/// among them.
const String _characters = 'ab:-?|>"\'\n\r\t {}[],#&*!%@`\\.';

/// Keys a codebase is named by: a codebase name, `[a-z][a-z0-9_]*`, ones
/// holding a line break, Unicode's among them, or another control
/// character, a list, and one no codebase name takes.
const List<String> _codebaseKeys = [
  'app',
  r'"a\nb"',
  r'"x\ry"',
  r'"a\u0007b"',
  r'"a\Nb"',
  r'"a\Lb"',
  r'"a\Pb"',
  r'"a\x7fb"',
  '[a, b]',
  '"1a"',
];

/// Keys a codebase holds: each it knows, one it does not, and one holding a
/// line break.
const List<String> _fieldKeys = [
  'git',
  'commit',
  'root',
  'toolchain',
  'depth',
  r'"de\npth"',
];

/// Values a key is given, each indented for a codebase's field: plain ones,
/// none, a null, flow and block lists and mappings, block scalars, and
/// quoted ones running over lines or holding Unicode's line breaks.
const List<String> _values = [
  '/srv/a.git',
  'go',
  '',
  '~',
  '[a, b]',
  '{a: b}',
  '\n      - a\n      - b',
  '\n      a: b',
  '|\n      a\n      b',
  '>\n      a\n      b',
  '"da\n      rt"',
  "'da\n      rt'",
  r'"da\Nrt"',
  r'"da\Lrt"',
];

/// A manifest of one codebase, keyed by [key], whose [field] is given
/// [value] over a codebase that would load.
String _codebase(String key, String field, String value) {
  final Map<String, String> fields = {
    'git': '/srv/a.git',
    'commit': _sha1,
    'toolchain': 'dart',
    field: value,
  };
  return [
    'codebases:',
    '  $key:',
    for (final MapEntry(key: String name, value: String given)
        in fields.entries)
      '    $name: $given',
    '',
  ].join('\n');
}

/// A manifest of one codebase whose fault sits at one place alone: a value
/// drawn for a key it knows, half the draws, else a key drawn for the
/// codebase or for one of its fields.
final Gen<String> _codebaseFault = .oneOf([
  .build(
    (Draw draw) => _codebase(
      'app',
      draw(.element(['commit', 'root', 'toolchain'])),
      draw(.element(_values)),
    ),
  ),
  .oneOf([
    .element(
      _codebaseKeys,
    ).map((String key) => _codebase(key, 'toolchain', 'dart')),
    .element(_fieldKeys).map((String field) => _codebase('app', field, 'dart')),
  ]),
]);

/// A manifest's bytes: a codebase with one fault drawn, or lines drawn from
/// [_lines] and from [_characters], with a byte no UTF-8 holds after them
/// where one is drawn.
final Gen<List<int>> _manifest = .oneOf([
  _codebaseFault.map(utf8.encode),
  .build((Draw draw) {
    final List<String> lines = draw(
      .list(.oneOf([.element(_lines), .string(alphabet: .of(_characters))])),
    );
    final bool notUtf8 = draw(.boolean());
    return [...utf8.encode(lines.join('\n')), if (notUtf8) 0xff];
  }),
]);

/// Every control character but a tab, and Unicode's line breaks beyond them.
final RegExp _controlButTab = .new(
  r'[\x00-\x08\x0a-\x1f\x7f-\x9f\u2028\u2029]',
);

/// The characters a manifest's file name is drawn from: letters, line
/// breaks, Unicode's among them, and another control character.
const String _nameCharacters = 'ab\n\r\x07\x85\u2028';

/// A path [os] reads as absolute.
String _absolute(Os os) => switch (os) {
  .posix => '/cache',
  .windows => r'C:\cache',
};

/// Text a refusal carries, drawn from [_characters] and [_nameCharacters],
/// control characters and line breaks among them.
final Gen<String> _text = .string(
  alphabet: .of('$_characters$_nameCharacters\x00\x1b\x9f'),
);

/// Drawn [_text] with no character either system reads as a separator, so
/// it stands as one part of a path.
final Gen<String> _part = _text.map(
  (String text) => text.replaceAll(RegExp(r'[/\\]'), ''),
);

/// A path [os] writes, of drawn [_text] in its directory and a drawn [_part]
/// in its file name, ending `.yaml` after a stem of its own.
Gen<ManifestPath> _manifestPath(Os os) => .build(
  (Draw draw) => .parse(
    os.paths.join(_absolute(os), draw(_text), 'a${draw(_part)}.yaml'),
    os,
  )!,
);

/// A key path of drawn keys from the top.
final Gen<KeyPath> _keyPath = .list(_text, maxLength: 4).map(pathOf);

/// A value a manifest wrote, of each [WrittenCase].
final Gen<Written> _written = .build((Draw draw) {
  final WrittenCase written = draw(.element(WrittenCase.values));
  return switch (written) {
    .text => WrittenText(draw(_text)),
    .list || .mapping || .nothing => written.sample,
  };
});

/// A manifest's refusal of each [ManifestRefusalCase], its key path, its
/// reason and what it wrote drawn.
final Gen<ManifestRefusal> _manifestRefusal = .build(
  (Draw draw) => switch (draw(.element(ManifestRefusalCase.values))) {
    .notYaml => NotYaml(draw(_text)),
    .unknownKey => UnknownKey(draw(_keyPath)),
    .missingKey => MissingKey(draw(_keyPath)),
    .missingKind => MissingKind(draw(_keyPath)),
    .badValue => BadValue(
      draw(_keyPath),
      draw(.element(Wanted.values)),
      draw(_written),
    ),
  },
);

/// A refusal of each [RefusalCase] on a drawn system, every path, reason
/// and system name it carries drawn.
final Gen<LoadRefusal> _refusal = .build((Draw draw) {
  final Os os = draw(.element(Os.values));
  ManifestPath manifest() => draw(_manifestPath(os));
  return switch (draw(.element(RefusalCase.values))) {
    .noManifest => NoManifest(.new(draw(_text), os)),
    .notManifestName => NotManifestName(draw(_text)),
    .manifestMissing => ManifestMissing(manifest()),
    .manifestUnreadable => ManifestUnreadable(manifest(), draw(_text)),
    .manifestInvalid => ManifestInvalid(manifest(), draw(_manifestRefusal)),
    .codebaseNamedTwice => CodebaseNamedTwice(
      .parse('a${draw(.string(alphabet: .lowerCase))}')!,
      first: manifest(),
      second: manifest(),
    ),
    .noWorkingDirectory => NoWorkingDirectory(draw(_text)),
    .noCache => NoCache(os),
    .noClaim => NoClaim(draw(_text)),
  };
});

/// The names a variable is drawn under: capitals, digits and underscores,
/// as a variable a system weighs is named.
final Gen<String> _variable = .string(
  alphabet: .of('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'),
  minLength: 1,
);

/// The variables [os] weighs, by their names.
Set<String> _weighedOn(Os os) => {
  for (final CacheVariable variable in CacheVariable.values)
    if (variable.weighedOn(os)) variable.variable,
};

/// The variables [text] names, every word of capitals and underscores.
Set<String> _variablesIn(String text) => {
  for (final RegExpMatch match in RegExp(r'\b[A-Z][A-Z_]*\b').allMatches(text))
    match[0]!,
};

void main() {
  property('LOA-10: Every `LoadRefusal` reads as one line holding no control '
      'character but a tab, whatever its paths and reasons hold, and so does '
      'the refusal of a load of any manifest at any path.', (Draw draw) async {
    final bool loaded = draw(.boolean(), label: 'loaded');
    if (!loaded) {
      final LoadRefusal refusal = draw(_refusal, label: 'refusal');
      expect('$refusal', isNot(contains(_controlButTab)));
      return;
    }
    final List<int> bytes = draw(_manifest, label: 'bytes');
    final String stem = draw(
      .string(alphabet: .of(_nameCharacters), minLength: 1),
      label: 'stem',
    );
    final String ending = draw(.element(['.yaml', '.yml']), label: 'ending');
    final bool missing = draw(
      .integer(min: 0, max: 3).map((int n) => n == 0),
      label: 'missing',
    );
    await inTemp((Directory temp) async {
      final String manifest = p.join(temp.path, 'manifests', '$stem$ending');
      if (!missing) {
        await File(manifest).create(recursive: true);
        await File(manifest).writeAsBytes(bytes);
      }
      final Load load = await loaderIn(
        temp,
        SpyRunner(hermetic(temp)),
        cached: false,
      ).load(named: [manifest]);
      switch (load) {
        case Refused(:final LoadRefusal reason):
          expect('$reason', isNot(contains(_controlButTab)));
        case Loaded():
          fail('a load with no cache loaded');
      }
    });
  }, settings: .new(shrinkSteps: gitShrinks));

  property('LOA-13: The `NoCache` text names exactly the variables its system '
      'weighs, each of which alone names a cache there, and no other variable '
      'does.', (Draw draw) {
    final Os os = draw(.element(Os.values), label: 'os');
    final List<String> others = draw(.list(_variable), label: 'others');
    final Set<String> weighed = _weighedOn(os);
    expect(_variablesIn('${NoCache(os)}'), weighed);
    for (final String variable in {...cacheVariables, ...others}) {
      expect(
        CacheDirectory.of((variables: {variable: _absolute(os)}, os: os)),
        weighed.contains(variable) ? isNotNull : isNull,
        reason: variable,
      );
    }
  });
}

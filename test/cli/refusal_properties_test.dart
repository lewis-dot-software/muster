import 'dart:convert';
import 'dart:io';

import 'package:glados/glados.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/cli/refusal_text.dart';
import 'package:muster/src/model/cache_directory.dart';

import '../support/git.dart';
import '../support/loads.dart';
import '../support/shrinking_at_most.dart';
import '../support/spy_runner.dart';

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

/// Names a codebase is keyed by: a pub package's, ones holding a line
/// break, Unicode's among them, or another control character, a list, and
/// one no package takes.
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
final Generator<String> _codebaseFault = any.either(
  any.combine2(
    any.choose(['commit', 'root', 'toolchain']),
    any.choose(_values),
    (String field, String value) => _codebase('app', field, value),
  ),
  any.either(
    any
        .choose(_codebaseKeys)
        .map((String key) => _codebase(key, 'toolchain', 'dart')),
    any
        .choose(_fieldKeys)
        .map((String field) => _codebase('app', field, 'dart')),
  ),
);

/// A manifest's bytes: a codebase with one fault drawn, or lines drawn from
/// [_lines] and from [_characters], with a byte no UTF-8 holds after them
/// where one is drawn.
final Generator<List<int>> _manifest = any
    .either(
      _codebaseFault.map(utf8.encode),
      any.combine2(
        any.list(any.either(any.choose(_lines), any.stringOf(_characters))),
        any.bool,
        (List<String> lines, bool notUtf8) => [
          ...utf8.encode(lines.join('\n')),
          if (notUtf8) 0xff,
        ],
      ),
    )
    .shrinkingAtMost(gitTries);

/// The lines [text] runs over, broken at every line break Unicode names.
List<String> _linesOf(String text) => text.split(_lineBreak);

final RegExp _lineBreak = .new(r'\r\n|[\n\x0b\x0c\r\x85\u2028\u2029]');

/// A path [os] reads as absolute.
String _absolute(Os os) => switch (os) {
  .posix => '/cache',
  .windows => r'C:\cache',
};

/// A variable the cache could be taken from, or a name of another.
final Generator<String> _variable = any.either(
  any.choose([...cacheVariables]),
  any.nonEmptyUppercaseLetters,
);

/// Whether [os] weighs [variable]: whether it alone, set to an absolute
/// path, gives a cache.
bool _weighs(Os os, String variable) =>
    CacheDirectory.of((variables: {variable: _absolute(os)}, os: os)) != null;

/// The variables [text] names, every word of capitals and underscores.
Set<String> _variablesIn(String text) => {
  for (final RegExpMatch match in RegExp(r'\b[A-Z][A-Z_]*\b').allMatches(text))
    match[0]!,
};

void main() {
  Glados(_manifest).test("Every refusal's text is one line, whatever the "
      'manifest holds.', (List<int> bytes) async {
    await inTemp((Directory temp) async {
      final String manifest = atRoot(temp);
      await File(manifest).create(recursive: true);
      await File(manifest).writeAsBytes(bytes);
      final Load load = await loaderIn(
        temp,
        SpyRunner(hermetic(temp)),
        cached: false,
      ).load();
      switch (load) {
        case Refused(:final LoadRefusal reason):
          expect(_linesOf(refusalText(reason)), hasLength(1));
        case Loaded():
          fail('a load with no cache loaded');
      }
    });
  });

  Glados2(any.choose(Os.values), any.list(_variable)).test(
    'The `NoCache` text names exactly the variables the running system '
    'weighs.',
    (Os os, List<String> others) {
      expect(_variablesIn(refusalText(NoCache(os))), {
        for (final String variable in [...cacheVariables, ...others])
          if (_weighs(os, variable)) variable,
      });
    },
  );
}

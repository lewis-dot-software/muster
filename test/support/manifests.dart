import 'package:grit/grit.dart';
import 'package:muster/src/model/breaks_line.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/codebase_name.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/key_path.dart';
import 'package:muster/src/model/quoted.dart';
import 'package:muster/src/model/resolution.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:yaml/yaml.dart';

/// One key and its value, as a manifest's text writes them.
typedef Field = (String key, String value);

/// One codebase as a manifest's text writes it: the key it stands under and
/// its fields, in order.
typedef Entry = (String name, List<Field> fields);

/// How a manifest's text writes each key and value.
enum Writing {
  /// In double quotes, so YAML reads each back as the string it is.
  quoted,

  /// Bare, as a consumer writes one, wherever YAML reads it back as written:
  /// as the string it is, or as a number, a bool or a null its text spells.
  /// Any other is quoted, since bare it would read as something else.
  plain,
}

/// The text of a manifest whose `codebases` holds [entries], with [top]'s
/// fields after it at the top, each key and value written as [writing] says.
String renderManifest(
  List<Entry> entries, {
  List<Field> top = const [],
  Writing writing = .quoted,
}) {
  String written(String text) => switch (writing) {
    .quoted => quoted(text),
    .plain => readsBare(text) ? text : quoted(text),
  };
  final StringBuffer text = .new();
  if (entries.isEmpty) {
    text.writeln('codebases: {}');
  } else {
    text.writeln('codebases:');
    for (final (String name, List<Field> fields) in entries) {
      if (fields.isEmpty) {
        text.writeln('  ${written(name)}: {}');
        continue;
      }
      text.writeln('  ${written(name)}:');
      for (final (String key, String value) in fields) {
        text.writeln('    ${written(key)}: ${written(value)}');
      }
    }
  }
  for (final (String key, String value) in top) {
    text.writeln('${written(key)}: ${written(value)}');
  }
  return '$text';
}

/// Whether [text], written bare, reads back as written: one line with no
/// space at either end, which a plain scalar drops, a plain scalar whose
/// span is the whole of it, and the string it is where YAML reads a string.
bool readsBare(String text) {
  if (text.isEmpty || breaksLine(text) || text.trim() != text) {
    return false;
  }
  final YamlNode node;
  try {
    node = loadYamlNode(text);
  } on YamlException {
    return false;
  }
  return switch (node) {
    YamlScalar(style: .PLAIN, :final Object? value)
        when node.span.text == text =>
      value is! String || value == text,
    _ => false,
  };
}

/// [codebase] as a manifest writes it, its root left out where it is the
/// repo's top.
Entry entryOf(GitCodebase codebase) => (
  codebase.name.name,
  [
    ('git', codebase.url.url),
    ('commit', codebase.commit.hash),
    if (codebase.root != .top) ('root', codebase.root.path),
    ('toolchain', codebase.toolchain.name),
  ],
);

/// [codebase] as a manifest writes it, its resolution left out where it is
/// `alone` and [resolutionOut] is set.
Entry hostedEntryOf(HostedCodebase codebase, {bool resolutionOut = false}) => (
  codebase.name.name,
  [
    ('hosted', codebase.package.name),
    ('version', codebase.version.version),
    if (!resolutionOut || codebase.resolution != .alone)
      ('resolution', codebase.resolution.word),
    ('toolchain', codebase.toolchain.name),
  ],
);

/// [codebase] as a manifest writes it, of either kind.
Entry anyEntryOf(Codebase codebase) => switch (codebase) {
  Git(codebase: final GitCodebase git) => entryOf(git),
  Hosted(codebase: final HostedCodebase hosted) => hostedEntryOf(hosted),
};

/// The path of [keys], each a key below the last, from the top.
KeyPath pathOf(List<String> keys) =>
    keys.fold(.top, (KeyPath path, String key) => path.child(key));

/// A codebase of the parts given, each of which must parse.
GitCodebase codebase(
  String name,
  String url,
  String commit,
  String root,
  Toolchain toolchain,
) => (
  name: .parse(name)!,
  url: .parse(url)!,
  commit: .parse(commit)!,
  root: .parse(root)!,
  toolchain: toolchain,
);

/// A hosted codebase of the parts given, each of which must parse.
HostedCodebase hosted(
  String name,
  String package,
  String version,
  Resolution resolution,
  Toolchain toolchain,
) => (
  name: .parse(name)!,
  package: .parse(package)!,
  version: .parse(version)!,
  resolution: resolution,
  toolchain: toolchain,
);

const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
const String _hex = '0123456789abcdef';
const String _letters = '${_lowercase}ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// The words pub refuses as a package's name, in any case, as pub's source
/// lists them.
const Set<String> pubReserved = {
  'abstract',
  'as',
  'assert',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'else',
  'enum',
  'export',
  'extends',
  'external',
  'false',
  'final',
  'finally',
  'for',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'inline',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

/// The words Dart reserves that pub takes as a package's name, since a
/// package on pub.dev already bears each.
const Set<String> pubLetStand = {
  'async',
  'base',
  'dynamic',
  'extension',
  'factory',
  'get',
  'show',
  'static',
  'sync',
  'typedef',
  'when',
};

/// A codebase's name, the words YAML reads bare as a null or a bool among
/// them.
final Gen<String> anyCodebaseName = .oneOf([
  .build(
    (Draw draw) =>
        draw(.element(_lowercase.split(''))) +
        draw(.string(alphabet: .of('${_lowercase}0123456789_'))),
  ),
  .element(['null', 'true', 'false']),
]);

/// A Dart identifier: one drawn letter by letter, one opening on `_` as
/// pub.dev's `_fe_analyzer_shared` does, or a word pub lets stand, in its
/// own case or capitalised.
final Gen<String> _identifier = .oneOf([
  .build(
    (Draw draw) =>
        draw(.element('${_letters}_'.split(''))) +
        draw(.string(alphabet: .of('${_letters}0123456789_'))),
  ),
  .element([
    '_fe_analyzer_shared',
    '_discoveryapis_commons',
    for (final String word in pubLetStand) ...[
      word,
      '${word[0].toUpperCase()}${word.substring(1)}',
    ],
  ]),
]);

/// A pub package's name, as `dart pub get` takes one: a Dart identifier,
/// or identifiers joined by `.`, given a `_` where the whole is a word pub
/// reserves.
final Gen<String> anyPackageName = .build((Draw draw) {
  final String name = [
    draw(_identifier),
    ...draw(.list(_identifier, maxLength: 2)),
  ].join('.');
  return pubReserved.contains(name.toLowerCase()) ? '${name}_' : name;
});

/// [length] lowercase hexadecimal digits.
Gen<String> hexOfLength(int length) =>
    .string(alphabet: .of(_hex), minLength: length, maxLength: length);

/// The digits a full hash is drawn from.
enum _HashForm {
  /// Any hexadecimal digits.
  hex,

  /// Decimal digits alone, which YAML reads bare as an integer.
  digits,

  /// Decimal digits either side of one `e`, which YAML reads bare as a
  /// float.
  exponent,
}

/// A full hash, SHA-1's or SHA-256's, in each of [_HashForm]'s forms.
final Gen<String> anyFullHash = .build((Draw draw) {
  final int length = draw(.element([40, 64]));
  return switch (draw(.element(_HashForm.values))) {
    .hex => draw(hexOfLength(length)),
    .digits => draw(_digitsOfLength(length)),
    .exponent =>
      '${draw(_digitsOfLength(1))}e${draw(_digitsOfLength(length - 2))}',
  };
});

/// [length] decimal digits.
Gen<String> _digitsOfLength(int length) =>
    .string(alphabet: .of('0123456789'), minLength: length, maxLength: length);

/// A root inside its repo, in its normal spelling, ones YAML reads bare as a
/// number, a bool or a null among them.
final Gen<String> anyNormalRoot = .list(
  .element([
    'pkgs',
    'app',
    'b_c',
    'tool',
    '1',
    '0x1f',
    'null',
    'Null',
    'NULL',
    '~',
    'true',
  ]),
).map((List<String> parts) => parts.isEmpty ? '.' : parts.join('/'));

/// A git URL.
final Gen<String> anyGitUrl = .build(
  (Draw draw) =>
      '${draw(.element(['https://example.com/', '/srv/', 'git@example.com:', 'file:///']))}'
      '${draw(.string(alphabet: .letters, minLength: 1))}.git',
);

/// A codebase, its parts drawn from [names], [urls], [commits] and [roots].
Gen<GitCodebase> anyGitCodebase({
  Gen<String>? names,
  Gen<String>? urls,
  Gen<String>? commits,
  Gen<String>? roots,
}) => .build(
  (Draw draw) => codebase(
    draw(names ?? anyCodebaseName),
    draw(urls ?? anyGitUrl),
    draw(commits ?? anyFullHash),
    draw(roots ?? anyNormalRoot),
    draw(.element(Toolchain.values)),
  ),
);

/// A manifest's codebases, each name once.
Gen<List<GitCodebase>> anyGitCodebases({Gen<String>? names}) =>
    .list(anyGitCodebase(names: names)).map(_uniqueGit);

/// A manifest's codebases, each name once, at least one of them.
final Gen<List<GitCodebase>> someGitCodebases = .list(
  anyGitCodebase(),
  minLength: 1,
).map(_uniqueGit);

/// Up to three dot-joined identifiers, each digits with no leading nought
/// or letters and `-`, or none.
final Gen<String> _identifiers = .list(
  .oneOf([
    .integer(min: 0, max: 999).map((int n) => '$n'),
    .build(
      (Draw draw) =>
          draw(.element(_lowercase.split(''))) +
          draw(.string(alphabet: .of('$_lowercase-'))),
    ),
  ]),
  maxLength: 3,
).map((List<String> parts) => parts.join('.'));

/// A version pub reads, in its canonical spelling: a `major.minor.patch`,
/// with a pre-release and a build where they are drawn.
final Gen<String> anyCanonicalVersion = .build((Draw draw) {
  final int major = draw(.integer(min: 0, max: 999));
  final int minor = draw(.integer(min: 0, max: 999));
  final int patch = draw(.integer(min: 0, max: 999));
  final String pre = draw(_identifiers);
  final String build = draw(_identifiers);
  return [
    '$major.$minor.$patch',
    if (pre.isNotEmpty) '-$pre',
    if (build.isNotEmpty) '+$build',
  ].join();
});

/// A hosted codebase, its parts drawn from [names], [packages] and
/// [versions].
Gen<HostedCodebase> anyHostedCodebase({
  Gen<String>? names,
  Gen<String>? packages,
  Gen<String>? versions,
}) => .build(
  (Draw draw) => hosted(
    draw(names ?? anyCodebaseName),
    draw(packages ?? anyPackageName),
    draw(versions ?? anyCanonicalVersion),
    draw(.element(Resolution.values)),
    draw(.element(Toolchain.values)),
  ),
);

/// A codebase of either kind, its name drawn from [names].
Gen<Codebase> anyCodebase({Gen<String>? names}) => .oneOf([
  anyGitCodebase(names: names).map(Git.new),
  anyHostedCodebase(names: names).map(Hosted.new),
]);

/// A manifest's codebases of either kind, each name once.
Gen<List<Codebase>> anyCodebases({Gen<String>? names}) =>
    .list(anyCodebase(names: names)).map(_uniqueCodebases);

/// A manifest's codebases of either kind, each name once, at least one of
/// them.
final Gen<List<Codebase>> someCodebases = .list(
  anyCodebase(),
  minLength: 1,
).map(_uniqueCodebases);

/// [codebases] with every codebase after the first whose [name] is its
/// dropped.
List<T> _uniqueBy<T>(List<T> codebases, CodebaseName Function(T) name) {
  final Set<CodebaseName> seen = {};
  return [
    for (final T codebase in codebases)
      if (seen.add(name(codebase))) codebase,
  ];
}

List<GitCodebase> _uniqueGit(List<GitCodebase> codebases) =>
    _uniqueBy(codebases, (GitCodebase codebase) => codebase.name);

List<Codebase> _uniqueCodebases(List<Codebase> codebases) =>
    _uniqueBy(codebases, (Codebase codebase) => codebase.name);

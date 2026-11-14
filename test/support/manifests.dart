import 'package:glados/glados.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/codebase_name.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/key_path.dart';
import 'package:muster/src/model/quoted.dart';
import 'package:muster/src/model/resolution.dart';
import 'package:muster/src/model/toolchain.dart';

/// One key and its value, as a manifest's text writes them.
typedef Field = (String key, String value);

/// One codebase as a manifest's text writes it: the key it stands under and
/// its fields, in order.
typedef Entry = (String name, List<Field> fields);

/// The text of a manifest whose `codebases` holds [entries], with [top]'s
/// fields after it at the top. Every key and value is quoted, so YAML reads
/// each back as the string it is.
String renderManifest(List<Entry> entries, {List<Field> top = const []}) {
  final StringBuffer text = .new();
  if (entries.isEmpty) {
    text.writeln('codebases: {}');
  } else {
    text.writeln('codebases:');
    for (final (String name, List<Field> fields) in entries) {
      if (fields.isEmpty) {
        text.writeln('  ${quoted(name)}: {}');
        continue;
      }
      text.writeln('  ${quoted(name)}:');
      for (final (String key, String value) in fields) {
        text.writeln('    ${quoted(key)}: ${quoted(value)}');
      }
    }
  }
  for (final (String key, String value) in top) {
    text.writeln('${quoted(key)}: ${quoted(value)}');
  }
  return '$text';
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

/// The generators the manifest's property tests draw from.
extension ManifestAnys on Any {
  /// A codebase's name.
  Generator<String> get codebaseName => combine2(
    choose(_lowercase.split('')),
    stringOf('${_lowercase}0123456789_'),
    (String head, String tail) => '$head$tail',
  );

  /// A pub package's name, as `dart pub get` takes one: a Dart identifier,
  /// or identifiers joined by `.`, given a `_` where the whole is a word pub
  /// reserves.
  Generator<String> get packageName => combine2(
    _identifier,
    listWithLengthInRange(0, 3, _identifier),
    (String head, List<String> tail) {
      final String name = [head, ...tail].join('.');
      return pubReserved.contains(name.toLowerCase()) ? '${name}_' : name;
    },
  );

  /// A Dart identifier: one drawn letter by letter, one opening on `_` as
  /// pub.dev's `_fe_analyzer_shared` does, or a word pub lets stand, in its
  /// own case or capitalised.
  Generator<String> get _identifier => either(
    combine2(
      choose('${_letters}_'.split('')),
      stringOf('${_letters}0123456789_'),
      (String head, String tail) => '$head$tail',
    ),
    choose([
      '_fe_analyzer_shared',
      '_discoveryapis_commons',
      for (final String word in pubLetStand) ...[
        word,
        '${word[0].toUpperCase()}${word.substring(1)}',
      ],
    ]),
  );

  /// [length] lowercase hexadecimal digits.
  Generator<String> hexOfLength(int length) =>
      listWithLength(length, choose(_hex.split(''))).map(_joined);

  /// A full hash, SHA-1's or SHA-256's.
  Generator<String> get fullHash => choose([40, 64]).bind(hexOfLength);

  /// A root inside its repo, in its normal spelling.
  Generator<String> get normalRoot =>
      list(choose(['pkgs', 'app', 'b_c', 'tool']))
          .map((List<String> parts) => parts.isEmpty ? '.' : parts.join('/'));

  /// A git URL.
  Generator<String> get gitUrl => combine2(
    choose(['https://example.com/', '/srv/', 'git@example.com:', 'file:///']),
    nonEmptyLetters,
    (String scheme, String name) => '$scheme$name.git',
  );

  /// A codebase, its parts drawn from [names], [urls], [commits] and [roots].
  Generator<GitCodebase> gitCodebase({
    Generator<String>? names,
    Generator<String>? urls,
    Generator<String>? commits,
    Generator<String>? roots,
  }) => combine5(
    names ?? codebaseName,
    urls ?? gitUrl,
    commits ?? fullHash,
    roots ?? normalRoot,
    choose(Toolchain.values),
    codebase,
  );

  /// A manifest's codebases, each name once.
  Generator<List<GitCodebase>> gitCodebases({Generator<String>? names}) =>
      list(gitCodebase(names: names)).map(_uniqueGit);

  /// A manifest's codebases, each name once, at least one of them.
  Generator<List<GitCodebase>> someGitCodebases() =>
      nonEmptyList(gitCodebase()).map(_uniqueGit);

  /// A version pub reads, in its canonical spelling: a `major.minor.patch`,
  /// with a pre-release and a build where they are drawn.
  Generator<String> get canonicalVersion => combine5(
    intInRange(0, 1000),
    intInRange(0, 1000),
    intInRange(0, 1000),
    _identifiers,
    _identifiers,
    (int major, int minor, int patch, String pre, String build) => [
      '$major.$minor.$patch',
      if (pre.isNotEmpty) '-$pre',
      if (build.isNotEmpty) '+$build',
    ].join(),
  );

  /// Up to three dot-joined identifiers, each digits with no leading nought
  /// or letters and `-`, or none.
  Generator<String> get _identifiers => listWithLengthInRange(
    0,
    4,
    either(
      intInRange(0, 1000).map((int n) => '$n'),
      combine2(
        choose(_lowercase.split('')),
        stringOf('$_lowercase-'),
        (String head, String tail) => '$head$tail',
      ),
    ),
  ).map((List<String> parts) => parts.join('.'));

  /// A hosted codebase, its parts drawn from [names], [packages] and
  /// [versions].
  Generator<HostedCodebase> hostedCodebase({
    Generator<String>? names,
    Generator<String>? packages,
    Generator<String>? versions,
  }) => combine5(
    names ?? codebaseName,
    packages ?? packageName,
    versions ?? canonicalVersion,
    choose(Resolution.values),
    choose(Toolchain.values),
    hosted,
  );

  /// A codebase of either kind, its name drawn from [names].
  Generator<Codebase> anyCodebase({Generator<String>? names}) => either(
    gitCodebase(names: names).map(Git.new),
    hostedCodebase(names: names).map(Hosted.new),
  );

  /// A manifest's codebases of either kind, each name once.
  Generator<List<Codebase>> codebases({Generator<String>? names}) =>
      list(anyCodebase(names: names)).map(_uniqueCodebases);

  /// A manifest's codebases of either kind, each name once, at least one of
  /// them.
  Generator<List<Codebase>> someCodebases() =>
      nonEmptyList(anyCodebase()).map(_uniqueCodebases);
}

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

String _joined(List<String> parts) => parts.join();

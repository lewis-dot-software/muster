import 'dart:convert';

import 'package:glados/glados.dart';
import 'package:muster/src/model/codebase_name.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/key_path.dart';
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
        text.writeln('  ${jsonEncode(name)}: {}');
        continue;
      }
      text.writeln('  ${jsonEncode(name)}:');
      for (final (String key, String value) in fields) {
        text.writeln('    ${jsonEncode(key)}: ${jsonEncode(value)}');
      }
    }
  }
  for (final (String key, String value) in top) {
    text.writeln('${jsonEncode(key)}: ${jsonEncode(value)}');
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

/// The path of [keys], each a key below the last, from the top.
KeyPath pathOf(List<String> keys) =>
    keys.fold(.top, (KeyPath path, String key) => path.child(key));

/// [codebases] with every codebase after the first of its name dropped.
List<GitCodebase> uniqueByName(List<GitCodebase> codebases) {
  final Set<CodebaseName> seen = {};
  return [
    for (final GitCodebase codebase in codebases)
      if (seen.add(codebase.name)) codebase,
  ];
}

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

const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
const String _hex = '0123456789abcdef';

/// The generators the manifest's property tests draw from.
extension ManifestAnys on Any {
  /// A pub package name.
  Generator<String> get packageName => combine2(
    choose(_lowercase.split('')),
    stringOf('${_lowercase}0123456789_'),
    (String head, String tail) => '$head$tail',
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
    names ?? packageName,
    urls ?? gitUrl,
    commits ?? fullHash,
    roots ?? normalRoot,
    choose(Toolchain.values),
    codebase,
  );

  /// A manifest's codebases, each name once.
  Generator<List<GitCodebase>> gitCodebases({Generator<String>? names}) =>
      list(gitCodebase(names: names)).map(uniqueByName);

  /// A manifest's codebases, each name once, at least one of them.
  Generator<List<GitCodebase>> someGitCodebases() =>
      nonEmptyList(gitCodebase()).map(uniqueByName);
}

String _joined(List<String> parts) => parts.join();

import 'package:yaml/yaml.dart';

import 'codebase_name.dart';
import 'commit.dart';
import 'git_codebase.dart';
import 'git_url.dart';
import 'key_path.dart';
import 'manifest.dart';
import 'manifest_parse.dart';
import 'manifest_refusal.dart';
import 'repo_root.dart';
import 'toolchain.dart';
import 'wanted.dart';

/// Reads a manifest's [text] into its codebases, or refuses it on the first
/// fault met: the top's unknown keys, then `codebases`, then each codebase in
/// the text's order, its name, its unknown keys, then `git`, `commit`, `root`
/// and `toolchain` in turn, each found and weighed before the next.
///
/// A plain value YAML reads as a number or a bool is taken as its text, so an
/// unquoted hash of digits alone is still a hash.
///
/// The text is one YAML mapping whose one key, `codebases`, maps each
/// codebase's name to its `git` URL, its `commit`, its `root`, `.` where it is
/// left out, and its `toolchain`.
ManifestParse parseManifest(String text) {
  try {
    return ManifestParsed(_manifest(_document(text)));
  } on _Refusal catch (e) {
    return ManifestRefused(e.refusal);
  }
}

/// The keys a manifest's top holds.
enum _TopKey { codebases }

/// The keys a git codebase holds.
enum _GitKey { git, commit, root, toolchain }

final Map<String, _TopKey> _topKeys = _TopKey.values.asNameMap();
final Map<String, _GitKey> _gitKeys = _GitKey.values.asNameMap();
final Map<String, Toolchain> _toolchains = Toolchain.values.asNameMap();

YamlNode _document(String text) {
  try {
    return loadYamlNode(text);
  } on YamlException catch (e) {
    throw _Refusal(NotYaml(e.toString()));
  }
}

Manifest _manifest(YamlNode document) {
  final YamlMap top = _mapping(document, .top);
  _knowOnly(top, .top, _topKeys);
  final KeyPath at = .top.child(_TopKey.codebases.name);
  final YamlMap codebases = _mapping(
    _required(top, .top, _TopKey.codebases),
    at,
  );
  return .new([
    for (final MapEntry<Object?, YamlNode>(:key, :value)
        in codebases.nodes.entries)
      _codebase(key as YamlNode, value, at),
  ]);
}

GitCodebase _codebase(YamlNode key, YamlNode value, KeyPath codebases) {
  final KeyPath at = codebases.child(key.value);
  final CodebaseName name =
      switch (_text(key)) {
        final String text => .parse(text),
        null => null,
      } ??
      (throw _Refusal(BadValue(at, .packageName, key.span.text)));
  final YamlMap fields = _mapping(value, at);
  _knowOnly(fields, at, _gitKeys);
  final YamlNode? root = fields.nodes[_GitKey.root.name];
  return (
    name: name,
    url: _field(fields, at, .git, .gitUrl, GitUrl.parse),
    commit: _field(fields, at, .commit, .fullHash, Commit.parse),
    root: root == null
        ? .top
        : _value(
            root,
            at.child(_GitKey.root.name),
            .rootInsideRepo,
            RepoRoot.parse,
          ),
    toolchain: _field(
      fields,
      at,
      .toolchain,
      .toolchain,
      (String word) => _toolchains[word],
    ),
  );
}

YamlMap _mapping(YamlNode node, KeyPath at) => node is YamlMap
    ? node
    : throw _Refusal(BadValue(at, .mapping, node.span.text));

void _knowOnly<K extends Enum>(YamlMap map, KeyPath at, Map<String, K> known) {
  for (final Object? key in map.keys) {
    if (key is! String || !known.containsKey(key)) {
      throw _Refusal(UnknownKey(at.child(key)));
    }
  }
}

YamlNode _required(YamlMap map, KeyPath at, Enum key) =>
    map.nodes[key.name] ?? (throw _Refusal(MissingKey(at.child(key.name))));

T _field<T>(
  YamlMap fields,
  KeyPath at,
  _GitKey key,
  Wanted wanted,
  T? Function(String text) parse,
) => _value(_required(fields, at, key), at.child(key.name), wanted, parse);

T _value<T>(
  YamlNode node,
  KeyPath at,
  Wanted wanted,
  T? Function(String text) parse,
) =>
    switch (_text(node)) {
      final String text => parse(text),
      null => null,
    } ??
    (throw _Refusal(BadValue(at, wanted, node.span.text)));

/// The text [node] holds: a string's own, or a number's or a bool's as
/// written, since YAML types a plain scalar before muster reads it. Null for a
/// mapping, a list or a null.
String? _text(YamlNode node) => switch (node) {
  YamlScalar(value: final String text) => text,
  YamlScalar(value: num() || bool()) => node.span.text,
  _ => null,
};

final class _Refusal implements Exception {
  const _Refusal(this.refusal);

  final ManifestRefusal refusal;
}

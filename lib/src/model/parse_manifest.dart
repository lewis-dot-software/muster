import 'package:yaml/yaml.dart';

import 'codebase.dart';
import 'codebase_name.dart';
import 'commit.dart';
import 'git_url.dart';
import 'key_path.dart';
import 'manifest.dart';
import 'manifest_parse.dart';
import 'manifest_refusal.dart';
import 'package_name.dart';
import 'package_version.dart';
import 'quiet_yaml_node.dart';
import 'repo_root.dart';
import 'resolution.dart';
import 'toolchain.dart';
import 'wanted.dart';
import 'written.dart';

/// Reads a manifest's [text] into its codebases, or refuses it on the first
/// fault met: the top's unknown keys, then `codebases`, then each codebase in
/// the text's order, its name, then its keys, then its kind's keys in turn,
/// each found and weighed before the next: `git`, `commit`, `root` and
/// `toolchain` for a git codebase, and `hosted`, `version`, `resolution` and
/// `toolchain` for a hosted one.
///
/// A codebase's kind is the one its first key of a kind's own names, and a
/// key of the other kind's is one muster does not know. A codebase holding no
/// key of either kind's refuses.
///
/// A plain value YAML reads as a number or a bool is taken as its text, so an
/// unquoted hash of digits alone is still a hash.
///
/// The text is one YAML mapping whose one key, `codebases`, maps each
/// codebase's name to its fields: a git codebase's `git` URL, its `commit`,
/// its `root`, `.` where it is left out, and its `toolchain`, or a hosted
/// one's `hosted` package, its `version`, its `resolution`, `alone` where it
/// is left out, and its `toolchain`.
ManifestParse parseManifest(String text) {
  try {
    return ManifestParsed(_manifest(_document(text)));
  } on _Refusal catch (e) {
    return ManifestRefused(e.refusal);
  }
}

/// The keys a manifest's top holds.
enum _TopKey { codebases }

/// The kinds of codebase a manifest names.
enum _Kind { git, hosted }

/// The keys a codebase holds.
enum _Key {
  git,
  commit,
  root,
  hosted,
  version,
  resolution,
  toolchain;

  /// The kind whose codebases alone hold the key, or null for a key both
  /// kinds hold.
  _Kind? get kind => switch (this) {
    .git || .commit || .root => .git,
    .hosted || .version || .resolution => .hosted,
    .toolchain => null,
  };
}

final Map<String, _TopKey> _topKeys = _TopKey.values.asNameMap();
final Map<String, _Key> _keys = _Key.values.asNameMap();

YamlNode _document(String text) {
  try {
    return quietYamlNode(text);
  } on YamlException catch (e) {
    throw _Refusal(NotYaml(_located(e)));
  }
}

/// [e]'s message after the line and column it stopped at, counted from 1,
/// with none of the source it would highlight.
String _located(YamlException e) =>
    switch ((e.span?.start.line, e.span?.start.column)) {
      (final int line, final int column) =>
        'line ${line + 1}, column ${column + 1}: ${e.message}',
      (null, _) || (_, null) => e.message,
    };

Manifest _manifest(YamlNode document) {
  final YamlMap top = _mapping(document, .top);
  for (final Object? key in top.keys) {
    if (key is! String || !_topKeys.containsKey(key)) {
      throw _Refusal(UnknownKey(.top.child(key)));
    }
  }
  final KeyPath at = .top.child(_TopKey.codebases.name);
  final YamlMap codebases = _mapping(
    top.nodes[_TopKey.codebases.name] ?? (throw _Refusal(MissingKey(at))),
    at,
  );
  return .new([
    for (final MapEntry<Object?, YamlNode>(:key, :value)
        in codebases.nodes.entries)
      _codebase(key as YamlNode, value, at),
  ]);
}

Codebase _codebase(YamlNode key, YamlNode value, KeyPath codebases) {
  final KeyPath at = codebases.child(key.value);
  final CodebaseName name =
      switch (_text(key)) {
        final String text => .parse(text),
        null => null,
      } ??
      (throw _Refusal(BadValue(at, .codebaseName, _written(key))));
  final _Fields fields = (map: _mapping(value, at), at: at);
  return switch (_kind(fields)) {
    .git => Git((
      name: name,
      url: _field(fields, .git, .gitUrl, GitUrl.parse),
      commit: _field(fields, .commit, .fullHash, Commit.parse),
      root: _fieldOr(fields, .root, .rootInsideRepo, RepoRoot.parse, .top),
      toolchain: _field(fields, .toolchain, .toolchain, Toolchain.parse),
    )),
    .hosted => Hosted((
      name: name,
      package: _field(fields, .hosted, .packageName, PackageName.parse),
      version: _field(fields, .version, .version, PackageVersion.parse),
      resolution: _fieldOr(
        fields,
        .resolution,
        .resolution,
        Resolution.parse,
        .alone,
      ),
      toolchain: _field(fields, .toolchain, .toolchain, Toolchain.parse),
    )),
  };
}

/// A codebase's mapping, and its path from the top.
typedef _Fields = ({YamlMap map, KeyPath at});

/// The kind of the codebase [fields] holds: the one its first key of a
/// kind's own names. Refuses on the first key, in the text's order, that
/// muster does not know or that is of the other kind's, and where no key is
/// of either kind's.
_Kind _kind(_Fields fields) {
  _Kind? kind;
  for (final Object? key in fields.map.keys) {
    final _Key? known = key is String ? _keys[key] : null;
    if (known == null) {
      throw _Refusal(UnknownKey(fields.at.child(key)));
    }
    final _Kind? own = known.kind;
    if (own == null) {
      continue;
    }
    kind ??= own;
    if (own != kind) {
      throw _Refusal(UnknownKey(fields.at.child(key)));
    }
  }
  return kind ?? (throw _Refusal(MissingKind(fields.at)));
}

T _field<T>(
  _Fields fields,
  _Key key,
  Wanted wanted,
  T? Function(String text) parse,
) => _value(
  fields.map.nodes[key.name] ??
      (throw _Refusal(MissingKey(fields.at.child(key.name)))),
  fields.at.child(key.name),
  wanted,
  parse,
);

/// The value of [key] in [fields], or [absent] where it is left out.
T _fieldOr<T>(
  _Fields fields,
  _Key key,
  Wanted wanted,
  T? Function(String text) parse,
  T absent,
) => switch (fields.map.nodes[key.name]) {
  final YamlNode node => _value(node, fields.at.child(key.name), wanted, parse),
  null => absent,
};

YamlMap _mapping(YamlNode node, KeyPath at) => node is YamlMap
    ? node
    : throw _Refusal(BadValue(at, .mapping, _written(node)));

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
    (throw _Refusal(BadValue(at, wanted, _written(node))));

/// The text [node] holds: a string's own, or a number's or a bool's as
/// written, since YAML types a plain scalar before muster reads it. Null for a
/// mapping, a list or a null.
String? _text(YamlNode node) => switch (node) {
  YamlScalar(value: final String text) => text,
  YamlScalar(value: num() || bool()) => node.span.text,
  _ => null,
};

/// What the manifest writes at [node]: a plain value's text as written, less
/// the line breaks a document's span ends on, or the kind of value a list, a
/// mapping or an empty value is. An empty value is a scalar of no text, or of
/// no style, since the span of an empty document holds its comments.
Written _written(YamlNode node) {
  final String text = node.span.text.trimRight();
  return switch (node) {
    YamlList() => const WrittenList(),
    YamlMap() => const WrittenMapping(),
    YamlScalar(style: .ANY) => const WrittenNothing(),
    _ when text.isEmpty => const WrittenNothing(),
    _ => WrittenText(text),
  };
}

final class _Refusal implements Exception {
  const _Refusal(this.refusal);

  final ManifestRefusal refusal;
}

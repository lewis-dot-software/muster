import 'key_path.dart';
import 'manifest_refusal.dart';
import 'on_one_line.dart';
import 'wanted.dart';
import 'written.dart';

/// Why a manifest's text refused, in one line for a person to act on, any
/// text in it holding a control character but a tab, or a line break, quoted
/// with each escaped.
String manifestRefusalText(ManifestRefusal refusal) => switch (refusal) {
  NotYaml(:final String reason) => 'not YAML: ${onOneLine(reason)}',
  UnknownKey(:final path) => _at(path, 'a key muster does not know'),
  MissingKey(:final path) => _at(path, 'missing'),
  MissingKind(:final path) => _at(path, 'neither git nor hosted'),
  BadValue(:final path, :final Wanted wanted, :final Written written) => _at(
    path,
    '${_writtenText(written)} is not ${_wantedText(wanted)}',
  ),
};

/// [text] after the key at [path], or alone where [path] is the top, which
/// no key names.
String _at(KeyPath path, String text) =>
    path == .top ? text : '${path.dotted}: $text';

String _writtenText(Written written) => switch (written) {
  WrittenText(:final String text) => onOneLine(text),
  WrittenList() => 'a list',
  WrittenMapping() => 'a mapping',
  WrittenNothing() => 'an empty value',
};

String _wantedText(Wanted wanted) => switch (wanted) {
  .mapping => 'a mapping',
  .codebaseName =>
    'a name of lowercase letters, digits and underscores, opening on a letter',
  .packageName => 'a pub package name',
  .gitUrl => 'a git URL',
  .fullHash => "a commit's full hash",
  .toolchain => 'dart or flutter',
  .rootInsideRepo => 'a relative path inside its repo',
  .version => 'a version pub reads',
  .resolution => 'alone or as-dependency',
};

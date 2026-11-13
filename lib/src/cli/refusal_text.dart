import 'dart:convert';

import '../model/key_path.dart';
import '../model/load_refusal.dart';
import '../model/manifest_refusal.dart';
import '../model/os.dart';
import '../model/wanted.dart';
import '../model/written.dart';

/// Why a run refused, in one line for a person to act on, any text in it
/// holding a control character or a line break quoted with each escaped.
String refusalText(LoadRefusal refusal) => switch (refusal) {
  NoManifest() =>
    'no manifest: none named, no muster.yaml in the working directory, and '
        'none in MUSTER_MANIFESTS',
  NotManifestName(:final String path) =>
    "${_line(path)}: a manifest's file name ends .yaml",
  ManifestMissing(:final manifest) =>
    '${_line(manifest.path)}: no such manifest',
  ManifestUnreadable(:final manifest, :final String reason) =>
    '${_line(manifest.path)}: ${_line(reason)}',
  ManifestInvalid(:final manifest, refusal: final ManifestRefusal why) =>
    '${_line(manifest.path)}: ${_manifestText(why)}',
  CodebaseNamedTwice(:final name, :final first, :final second) =>
    '${name.name}: named in ${_line(first.path)} and again in '
        '${_line(second.path)}',
  NoWorkingDirectory(:final String reason) =>
    'no working directory: ${_line(reason)}',
  NoCache(:final Os os) => 'no cache: ${_cacheText(os)}',
  NoClaim(:final String system) =>
    'no claim: muster knows no C library to lock a claim with on '
        '${_line(system)}',
};

/// The variables [os] takes the cache from, none of them set.
String _cacheText(Os os) => switch (os) {
  .posix =>
    'none of MUSTER_CACHE, XDG_CACHE_HOME as an absolute path, or HOME is '
        'set',
  .windows => 'neither MUSTER_CACHE nor LOCALAPPDATA is set',
};

String _manifestText(ManifestRefusal refusal) => switch (refusal) {
  NotYaml(:final String reason) => 'not YAML: ${_line(reason)}',
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
    path == .top ? text : '${_line(path.dotted)}: $text';

String _writtenText(Written written) => switch (written) {
  WrittenText(:final String text) => _line(text),
  WrittenList() => 'a list',
  WrittenMapping() => 'a mapping',
  WrittenNothing() => 'an empty value',
};

String _wantedText(Wanted wanted) => switch (wanted) {
  .mapping => 'a mapping',
  .packageName => 'a pub package name',
  .gitUrl => 'a git URL',
  .fullHash => "a commit's full hash",
  .toolchain => 'dart or flutter',
  .rootInsideRepo => 'a relative path inside its repo',
  .version => 'a version pub reads',
  .resolution => 'alone or as-dependency',
};

/// [text] as it stands, or quoted as a JSON string where it holds a control
/// character but a tab or a line break Unicode names, so it never breaks the
/// line: each of those escaped, the ones `jsonEncode` leaves among them.
String _line(String text) => text.contains(_breaking)
    ? jsonEncode(text).replaceAllMapped(
        _unescaped,
        (Match match) =>
            '\\u${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
      )
    : text;

/// Every control character but a tab, and Unicode's line breaks beyond them.
final RegExp _breaking = .new(r'[\x00-\x08\x0a-\x1f\x7f-\x9f\u2028\u2029]');

/// What [_breaking] holds that `jsonEncode` writes as it stands.
final RegExp _unescaped = .new(r'[\x7f-\x9f\u2028\u2029]');

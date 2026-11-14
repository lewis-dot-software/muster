import 'breaks_line.dart';
import 'quoted.dart';

/// Where a key sits in a manifest, each key from the top joined by `.`, as
/// `codebases.app.root` is. A key that is empty, holds a `.`, opens on `"` or
/// holds a character that breaks a line is quoted, as `codebases."a.b"` is,
/// so two paths are the same exactly when their keys are.
extension type const KeyPath._(String dotted) {
  /// The top of a manifest, above every key.
  static const KeyPath top = ._('');

  /// The path of [key], as the manifest writes it, inside the mapping at
  /// this path.
  KeyPath child(String key) {
    final String named = _bare(key) ? key : quoted(key);
    return ._(dotted.isEmpty ? named : '$dotted.$named');
  }
}

/// Whether [key] reads as itself in a path, unquoted.
bool _bare(String key) =>
    key.isNotEmpty &&
    !key.contains('.') &&
    !key.startsWith('"') &&
    !breaksLine(key);

import 'package:path/path.dart' as p;

/// The directory of the package inside a git codebase's repo that resolves
/// and is handed out, relative to the repo's top, in `/` separators and
/// normalised, so two spellings of one directory are one root.
extension type const RepoRoot._(String path) {
  /// The repo's top, the root where a manifest leaves it out.
  static const RepoRoot top = ._('.');

  /// The root [text] names, or null where it leaves its repo: an absolute
  /// path, one that climbs above the top, or one holding `\`, which Windows
  /// reads as a separator.
  static RepoRoot? parse(String text) {
    if (text.contains(r'\') ||
        p.posix.isAbsolute(text) ||
        p.windows.isAbsolute(text)) {
      return null;
    }
    final String normal = p.posix.normalize(text);
    return normal == '..' || normal.startsWith('../') ? null : ._(normal);
  }
}

import 'package:path/path.dart' as p;

import 'repo_root.dart';

/// A path inside a git repo, relative to its top, in `/` separators and
/// normalised, as git lists one.
extension type const RepoPath._(String path) {
  /// The path of [root] inside its repo.
  static RepoPath of(RepoRoot root) => ._(root.path);

  /// The path git lists as [text].
  static RepoPath listed(String text) => ._(text);

  /// The path of [child] under this one, normalised.
  RepoPath join(String child) =>
      ._(p.posix.normalize(p.posix.join(path, child)));

  /// The path's parts, in order.
  List<String> get segments => path.split('/');
}

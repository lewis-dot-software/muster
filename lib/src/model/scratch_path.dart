import 'os.dart';
import 'worktree_path.dart';

/// The directory of one scratch, a worktree of a clone made in a temporary
/// directory of its own.
extension type const ScratchPath._(({String path, Os os}) _scratch)
    implements WorktreePath {
  /// The scratch at [path], written in [os]'s paths.
  ScratchPath(String path, Os os) : this._((path: path, os: os));
}

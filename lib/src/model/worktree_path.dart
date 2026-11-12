import 'os.dart';

/// The directory of a worktree of a clone, a checkout's or a scratch's, and
/// the system whose paths it is written in.
extension type const WorktreePath._(({String path, Os os}) _worktree) {
  /// The worktree's path.
  String get path => _worktree.path;

  /// The system whose paths the worktree, and every path inside it, is
  /// written in.
  Os get os => _worktree.os;
}

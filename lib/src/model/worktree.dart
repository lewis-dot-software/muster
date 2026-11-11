import 'commit.dart';

/// What a checkout's git status shows of it: the commit its [head] stands
/// at, and whether any tracked file has [changed] from it, in the index or
/// on disk.
typedef Worktree = ({Commit head, bool changed});

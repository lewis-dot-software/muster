import '../model/command.dart';
import '../model/worktree_path.dart';

/// Git's [arguments] in the worktree at [worktree], its repo and worktree
/// named there, so git never climbs to a repo around it, as it would where
/// the worktree's `.git` is gone.
Command gitIn(WorktreePath worktree, List<String> arguments) => (
  executable: .git,
  arguments: [
    '-C',
    worktree.path,
    '--git-dir=.git',
    '--work-tree=.',
    ...arguments,
  ],
);

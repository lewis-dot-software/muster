import '../model/commit.dart';
import '../model/worktree_path.dart';
import 'git_in.dart';
import 'runner.dart';
import 'store_fault.dart';

/// The worktree at [worktree] moved to [commit] by [runner], holding its
/// tracked files alone: checked out there by force, every tracked file's
/// edit reverted, and cleaned of every file the commit lacks, ignored ones
/// among them.
///
/// Throws a [StoreFault] where git fails.
Future<void> moveWorktree(
  Runner runner,
  WorktreePath worktree,
  Commit commit,
) async {
  await runner.run(
    gitIn(worktree, [
      'checkout',
      '--quiet',
      '--force',
      '--detach',
      commit.hash,
    ]),
  );
  await runner.run(gitIn(worktree, ['clean', '-ffdxq']));
}

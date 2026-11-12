import '../model/clone_path.dart';
import '../model/commit.dart';
import '../model/worktree_path.dart';
import 'git_on.dart';
import 'runner.dart';
import 'store_fault.dart';

/// A worktree of [clone] added at [worktree] by [runner], detached at
/// [commit], the clone's worktrees pruned first, so one whose directory was
/// deleted by hand never blocks it.
///
/// Throws a [StoreFault] where git fails.
Future<void> addWorktree(
  Runner runner,
  ClonePath clone,
  WorktreePath worktree,
  Commit commit,
) async {
  await runner.run(gitOn(clone, ['worktree', 'prune']));
  await runner.run(
    gitOn(clone, [
      'worktree',
      'add',
      '--quiet',
      '--detach',
      worktree.path,
      commit.hash,
    ]),
  );
}

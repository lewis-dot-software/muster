import 'commit.dart';
import 'worktree.dart';

/// The worktree [output] shows, the output of
/// `git status --porcelain=v2 --branch -z --untracked-files=no`, or null
/// where it names no commit at `HEAD`.
///
/// Any entry past the headers is a tracked file changed, since untracked
/// files are left out and ignored files are never listed.
Worktree? readStatus(String output) {
  Commit? head;
  bool changed = false;
  for (final String entry in output.split('\x00')) {
    if (entry.isEmpty) {
      continue;
    }
    if (entry.startsWith('# ')) {
      if (entry.startsWith(_oid)) {
        head = .parse(entry.substring(_oid.length));
      }
      continue;
    }
    changed = true;
  }
  return switch (head) {
    final Commit head => (head: head, changed: changed),
    null => null,
  };
}

const String _oid = '# branch.oid ';

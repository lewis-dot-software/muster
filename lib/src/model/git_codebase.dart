import 'codebase_name.dart';
import 'commit.dart';
import 'git_url.dart';
import 'repo_root.dart';
import 'toolchain.dart';

/// A codebase a manifest names by git: its [name], the [url] it is cloned
/// from, the [commit] it is pinned at, the [root] of the package inside its
/// repo, and the [toolchain] that resolves it.
typedef GitCodebase = ({
  CodebaseName name,
  GitUrl url,
  Commit commit,
  RepoRoot root,
  Toolchain toolchain,
});

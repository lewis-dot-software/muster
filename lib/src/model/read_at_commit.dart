import 'at_commit.dart';
import 'package.dart';
import 'repo_path.dart';
import 'repo_root.dart';

/// What a commit holds of the packages of a codebase whose root is [root],
/// from the files the commit [listed]: the root always, the example where its
/// `pubspec.yaml` is listed, and each of those whose `pubspec.lock` is listed
/// as locked.
AtCommit readAtCommit(RepoRoot root, Set<RepoPath> listed) {
  final Set<Package> packages = {
    .root,
    if (listed.contains(Package.example.fileInRepo(root, .pubspec))) .example,
  };
  return (
    packages: packages,
    locked: {
      for (final Package package in packages)
        if (listed.contains(package.fileInRepo(root, .lock))) package,
    },
  );
}

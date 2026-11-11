import 'package.dart';
import 'repo_path.dart';
import 'repo_root.dart';

/// The files of a commit whose presence sets what it holds of the packages
/// of a codebase whose root is [root]: each package's `pubspec.lock`, and the
/// example's `pubspec.yaml`.
List<RepoPath> atCommitFiles(RepoRoot root) => [
  for (final Package package in Package.values) package.fileInRepo(root, .lock),
  Package.example.fileInRepo(root, .pubspec),
];

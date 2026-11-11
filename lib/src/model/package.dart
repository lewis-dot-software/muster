import 'package_file.dart';
import 'repo_path.dart';
import 'repo_root.dart';

/// A package a git codebase resolves.
enum Package {
  /// The codebase's root, the package handed out.
  root,

  /// The `example/` inside the root, where it holds a pubspec of its own.
  example;

  /// The package's directory inside its repo, for a codebase whose root is
  /// [root].
  RepoPath inRepo(RepoRoot root) => switch (this) {
    .root => .of(root),
    .example => .of(root).join('example'),
  };

  /// The package's [file] inside its repo, for a codebase whose root is
  /// [root].
  RepoPath fileInRepo(RepoRoot root, PackageFile file) =>
      inRepo(root).join(file.name);
}

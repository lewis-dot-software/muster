import 'checkout_path.dart';
import 'lock_path.dart';
import 'os.dart';
import 'package.dart';
import 'package_config_path.dart';
import 'package_file.dart';
import 'repo_root.dart';
import 'scratch_path.dart';

/// The directory of one package inside a checkout or a scratch.
extension type const PackagePath._(({String path, Os os}) _package) {
  /// The [package] of a codebase whose root is [root], inside [checkout].
  static PackagePath of(
    CheckoutPath checkout,
    RepoRoot root,
    Package package,
  ) => _inWorktree(checkout.path, checkout.os, root, package);

  /// The package at [root], the codebase's root, inside [scratch].
  static PackagePath inScratch(ScratchPath scratch, RepoRoot root) =>
      _inWorktree(scratch.path, scratch.os, root, .root);

  /// The [package] of a codebase whose root is [root], inside the worktree
  /// at [worktree], written in [os]'s paths.
  static PackagePath _inWorktree(
    String worktree,
    Os os,
    RepoRoot root,
    Package package,
  ) => ._((
    path: os.paths.normalize(
      os.paths.joinAll([worktree, ...package.inRepo(root).segments]),
    ),
    os: os,
  ));

  /// The package's path.
  String get path => _package.path;

  /// The package's `pubspec.lock`.
  LockPath get lock =>
      .inPackage(_package.os.paths.join(path, PackageFile.lock.name));

  /// The `package_config.json` a resolve of the package writes.
  PackageConfigPath get packageConfig => .inPackage(
    _package.os.paths.join(path, '.dart_tool', 'package_config.json'),
  );
}

import 'checkout_path.dart';
import 'lock_path.dart';
import 'os.dart';
import 'package.dart';
import 'package_config_path.dart';
import 'package_file.dart';
import 'repo_root.dart';

/// The directory of one package inside a checkout.
extension type const PackagePath._(({String path, Os os}) _package) {
  /// The [package] of a codebase whose root is [root], inside [checkout].
  static PackagePath of(
    CheckoutPath checkout,
    RepoRoot root,
    Package package,
  ) => ._((
    path: checkout.os.paths.normalize(
      checkout.os.paths.joinAll([
        checkout.path,
        ...package.inRepo(root).segments,
      ]),
    ),
    os: checkout.os,
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

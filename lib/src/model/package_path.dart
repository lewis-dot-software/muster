import 'checkout_path.dart';
import 'codebase.dart';
import 'git_codebase.dart';
import 'hosted_codebase.dart';
import 'lock_path.dart';
import 'os.dart';
import 'package.dart';
import 'package_config_path.dart';
import 'package_file.dart';
import 'pubspec_overrides_path.dart';
import 'pubspec_path.dart';
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

  /// The directory [codebase]'s [package] resolves in, inside [checkout],
  /// as [of] gives a git codebase's and [ofHosted] a hosted one's.
  static PackagePath inCheckout(
    CheckoutPath checkout,
    Codebase codebase,
    Package package,
  ) => switch (codebase) {
    Git(codebase: final GitCodebase git) => .of(checkout, git.root, package),
    Hosted(codebase: final HostedCodebase hosted) => .ofHosted(
      checkout,
      hosted,
      package,
    ),
  };

  /// The directory `dart pub unpack` unpacks [codebase]'s package into,
  /// inside [checkout]: `<package>-<version>`.
  static PackagePath unpacked(CheckoutPath checkout, HostedCodebase codebase) =>
      ._((
        path: checkout.os.paths.join(
          checkout.path,
          '${codebase.package.name}-${codebase.version.version}',
        ),
        os: checkout.os,
      ));

  /// The directory [codebase]'s [package] resolves in, inside [checkout]:
  /// for the root, the checkout's top where it resolves as a dependency of
  /// the package around it, and else its [unpacked] package, and for the
  /// example, the `example/` inside that package.
  static PackagePath ofHosted(
    CheckoutPath checkout,
    HostedCodebase codebase,
    Package package,
  ) {
    final PackagePath unpacked = .unpacked(checkout, codebase);
    return switch ((package, codebase.resolution)) {
      (.root, .alone) => unpacked,
      (.root, .asDependency) => ._((path: checkout.path, os: checkout.os)),
      (.example, _) => ._((
        path: checkout.os.paths.join(unpacked.path, 'example'),
        os: checkout.os,
      )),
    };
  }

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

  /// The package's `pubspec.yaml`.
  PubspecPath get pubspec =>
      .inPackage(_package.os.paths.join(path, PackageFile.pubspec.name));

  /// The package's `pubspec_overrides.yaml`.
  PubspecOverridesPath get overrides =>
      .inPackage(_package.os.paths.join(path, 'pubspec_overrides.yaml'));

  /// The package's `pubspec.lock`.
  LockPath get lock =>
      .inPackage(_package.os.paths.join(path, PackageFile.lock.name));

  /// The `package_config.json` a resolve of the package writes.
  PackageConfigPath get packageConfig => .inPackage(
    _package.os.paths.join(path, '.dart_tool', 'package_config.json'),
  );
}

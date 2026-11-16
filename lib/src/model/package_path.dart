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

/// The directory of one package inside a checkout or a scratch, beside the
/// directory its resolve runs in: its own, or that of the package around it
/// where it resolves as a dependency of that package.
extension type const PackagePath._(
  ({String path, String resolvedIn, Os os}) _package,
) {
  /// The package's path.
  String get path => _package.path;

  /// The package's `pubspec.yaml`.
  PubspecPath get pubspec =>
      .inPackage(_package.os.paths.join(path, PackageFile.pubspec.name));

  /// The package's `pubspec_overrides.yaml`.
  PubspecOverridesPath get overrides =>
      .inPackage(_package.os.paths.join(path, 'pubspec_overrides.yaml'));

  /// The `pubspec.lock` the package's resolve writes.
  LockPath get lock => .inPackage(
    _package.os.paths.join(_package.resolvedIn, PackageFile.lock.name),
  );

  /// The `package_config.json` the package's resolve writes.
  PackageConfigPath get packageConfig => .inPackage(
    _package.os.paths.join(
      _package.resolvedIn,
      '.dart_tool',
      'package_config.json',
    ),
  );
}

/// The package at [path], in [os]'s paths, whose resolve runs in it.
PackagePath _resolvingAlone(String path, Os os) =>
    ._((path: path, resolvedIn: path, os: os));

/// The [package] of a codebase whose root is [root], inside [checkout].
PackagePath packageIn(CheckoutPath checkout, RepoRoot root, Package package) =>
    _inWorktree(checkout.path, checkout.os, root, package);

/// The directory [codebase]'s [package] resolves in, inside [checkout], as
/// [packageIn] gives a git codebase's and [hostedPackage] a hosted one's.
PackagePath packageInCheckout(
  CheckoutPath checkout,
  Codebase codebase,
  Package package,
) => switch (codebase) {
  Git(codebase: final GitCodebase git) => packageIn(
    checkout,
    git.root,
    package,
  ),
  Hosted(codebase: final HostedCodebase hosted) => hostedPackage(
    checkout,
    hosted,
    package,
  ),
};

/// The package [codebase]'s checkout at [checkout] hands a tool: a git
/// codebase's root, and a hosted one's [unpackedPackage].
PackagePath handedOut(CheckoutPath checkout, Codebase codebase) =>
    switch (codebase) {
      Git(codebase: final GitCodebase git) => packageIn(
        checkout,
        git.root,
        .root,
      ),
      Hosted(codebase: final HostedCodebase hosted) => unpackedPackage(
        checkout,
        hosted,
      ),
    };

/// The directory `dart pub unpack` unpacks [codebase]'s package into, inside
/// [checkout], `<package>-<version>`, its lock and package config those of
/// the package around it in the checkout's top where it resolves as a
/// dependency of that package.
PackagePath unpackedPackage(CheckoutPath checkout, HostedCodebase codebase) {
  final String unpacked = _unpackedIn(checkout, codebase);
  return ._((
    path: unpacked,
    resolvedIn: switch (codebase.resolution) {
      .alone => unpacked,
      .asDependency => checkout.path,
    },
    os: checkout.os,
  ));
}

/// The directory [codebase]'s [package] resolves in, inside [checkout]: for
/// the root, the checkout's top where it resolves as a dependency of the
/// package around it, and else its [unpackedPackage], and for the example,
/// the `example/` inside that package.
PackagePath hostedPackage(
  CheckoutPath checkout,
  HostedCodebase codebase,
  Package package,
) => switch ((package, codebase.resolution)) {
  (.root, .alone) => unpackedPackage(checkout, codebase),
  (.root, .asDependency) => _resolvingAlone(checkout.path, checkout.os),
  (.example, _) => _resolvingAlone(
    checkout.os.paths.join(_unpackedIn(checkout, codebase), 'example'),
    checkout.os,
  ),
};

/// The path of the directory `dart pub unpack` unpacks [codebase]'s package
/// into, inside [checkout].
String _unpackedIn(CheckoutPath checkout, HostedCodebase codebase) =>
    checkout.os.paths.join(
      checkout.path,
      '${codebase.package.name}-${codebase.version.version}',
    );

/// The package at [root], the codebase's root, inside [scratch].
PackagePath packageInScratch(ScratchPath scratch, RepoRoot root) =>
    _inWorktree(scratch.path, scratch.os, root, .root);

/// The [package] of a codebase whose root is [root], inside the worktree at
/// [worktree], written in [os]'s paths.
PackagePath _inWorktree(
  String worktree,
  Os os,
  RepoRoot root,
  Package package,
) => _resolvingAlone(
  os.paths.normalize(
    os.paths.joinAll([worktree, ...package.inRepo(root).segments]),
  ),
  os,
);

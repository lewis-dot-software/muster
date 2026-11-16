import 'dart:convert';

import 'package:grit/grit.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/content_hash.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/lock_source.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/sdk_version.dart';
import 'package:muster/src/model/stamp.dart';
import 'package:muster/src/model/stamped_package.dart';
import 'package:muster/src/model/stands.dart';
import 'package:muster/src/model/survey.dart';
import 'package:muster/src/model/surveyed_package.dart';
import 'package:muster/src/model/worktree.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';
import '../support/stamps.dart';

/// One way a survey can fall off what its stamp names.
enum _Off {
  /// The manifest names another URL.
  url,

  /// The manifest names another commit.
  commit,

  /// The manifest names another root.
  root,

  /// The manifest names another toolchain.
  toolchain,

  /// The SDK on `PATH` is another version.
  sdk,

  /// No stamp is there, or it holds none.
  stamp,

  /// No worktree git can read is there.
  worktree,

  /// The package handed out holds no pubspec.
  handedOutGone,

  /// `HEAD` stands at another commit.
  head,

  /// A tracked file has changed.
  changed,

  /// A package's lock in the checkout is another.
  lock,

  /// A kept lock a package resolved on is another.
  keptLock,

  /// A package's kept lock it resolved on is gone.
  keptLockGone,

  /// A package's `package_config.json` is another.
  packageConfig,

  /// A package's `package_config.json` is gone.
  packageConfigGone,
}

/// A change to what a survey reads that is none of the stamp's business: a
/// kept lock of a package that resolved on its commit's, or a package the
/// stamp does not name.
enum _Noise { committedKeptLock, unstampedPackage }

/// Another hash than [hash].
ContentHash _other(ContentHash hash) => .of(utf8.encode(hash.hex));

/// Another commit than [commit].
Commit _otherCommit(Commit commit) => .parse(
  '${commit.hash.startsWith('a') ? 'b' : 'a'}${commit.hash.substring(1)}',
)!;

/// [packages] with every package that falls on a kept lock made to resolve
/// on one, so a kept lock's change has a package to land on.
Map<Package, StampedPackage> _keptWhereOff(
  Map<Package, StampedPackage> packages,
  Package at,
  Set<_Off> offs,
) => {
  for (final MapEntry<Package, StampedPackage>(:key, :value)
      in packages.entries)
    key: key == at && offs.any({_Off.keptLock, _Off.keptLockGone}.contains)
        ? (source: .kept, lock: value.lock, packageConfig: value.packageConfig)
        : value,
};

/// The survey of a checkout stamped [stamp] at [commit] that stands, then
/// fallen off by [offs] on its package [at], and changed by [noise].
Survey _survey(
  Stamp stamp,
  Commit commit,
  Set<_Off> offs,
  Set<_Noise> noise,
  Package at,
) {
  final Map<Package, SurveyedPackage> packages = {
    for (final Package package in Package.values)
      package: switch (stamp.packages[package]) {
        final StampedPackage stamped => (
          lock: package == at && offs.contains(_Off.lock)
              ? _other(stamped.lock)
              : stamped.lock,
          keptLock: switch (stamped.source) {
            .kept when package == at && offs.contains(_Off.keptLockGone) =>
              null,
            .kept when package == at && offs.contains(_Off.keptLock) => _other(
              stamped.lock,
            ),
            .kept => stamped.lock,
            .committed when noise.contains(_Noise.committedKeptLock) => _other(
              stamped.lock,
            ),
            .committed => null,
          },
          packageConfig: package == at && offs.contains(_Off.packageConfigGone)
              ? null
              : package == at && offs.contains(_Off.packageConfig)
              ? _other(stamped.packageConfig)
              : stamped.packageConfig,
        ),
        null when noise.contains(_Noise.unstampedPackage) => (
          lock: stamp.packages[Package.root]!.lock,
          keptLock: stamp.packages[Package.root]!.lock,
          packageConfig: stamp.packages[Package.root]!.packageConfig,
        ),
        null => (lock: null, keptLock: null, packageConfig: null),
      },
  };
  final Worktree worktree = (
    head: offs.contains(_Off.head) ? _otherCommit(commit) : commit,
    changed: offs.contains(_Off.changed),
  );
  return (
    sdk: offs.contains(_Off.sdk) ? .parse('${stamp.sdk.version}9')! : stamp.sdk,
    stamp: offs.contains(_Off.stamp) ? null : stamp,
    worktree: offs.contains(_Off.worktree) ? null : worktree,
    there: !offs.contains(_Off.handedOutGone),
    packages: packages,
  );
}

/// [codebase] as the manifest names it once [offs] edit it.
GitCodebase _edited(GitCodebase codebase, Set<_Off> offs) => (
  name: codebase.name,
  url: offs.contains(_Off.url) ? .parse('${codebase.url.url}x')! : codebase.url,
  commit: offs.contains(_Off.commit)
      ? _otherCommit(codebase.commit)
      : codebase.commit,
  root: offs.contains(_Off.root)
      ? (codebase.root == .top ? .parse('other')! : .top)
      : codebase.root,
  toolchain: offs.contains(_Off.toolchain)
      ? switch (codebase.toolchain) {
          .dart => .flutter,
          .flutter => .dart,
        }
      : codebase.toolchain,
);

/// One way a hosted checkout's survey can fall off what its stamp names.
enum _HostedOff {
  /// The manifest names another package.
  package,

  /// The manifest names another version.
  version,

  /// The manifest names another resolution.
  resolution,

  /// The manifest names another toolchain.
  toolchain,

  /// The SDK on `PATH` is another version.
  sdk,

  /// No stamp is there, or it holds none.
  stamp,

  /// The package handed out holds no pubspec.
  handedOutGone,

  /// A package's lock in the checkout is another.
  lock,

  /// A package's kept lock is another.
  keptLock,

  /// A package's kept lock is gone.
  keptLockGone,

  /// A package's `package_config.json` is another.
  packageConfig,

  /// A package's `package_config.json` is gone.
  packageConfigGone,
}

/// [codebase] as the manifest names it once [offs] edit it.
HostedCodebase _editedHosted(HostedCodebase codebase, Set<_HostedOff> offs) => (
  name: codebase.name,
  package: offs.contains(_HostedOff.package)
      ? .parse('${codebase.package.name}x')!
      : codebase.package,
  version: offs.contains(_HostedOff.version)
      ? .parse('${codebase.version.version}-x')!
      : codebase.version,
  resolution: offs.contains(_HostedOff.resolution)
      ? switch (codebase.resolution) {
          .alone => .asDependency,
          .asDependency => .alone,
        }
      : codebase.resolution,
  toolchain: offs.contains(_HostedOff.toolchain)
      ? switch (codebase.toolchain) {
          .dart => .flutter,
          .flutter => .dart,
        }
      : codebase.toolchain,
);

/// The survey of a hosted checkout stamped [stamp] that stands, carrying
/// [worktree], then fallen off by [offs] on its package [at].
Survey _hostedSurvey(
  Stamp stamp,
  Set<_HostedOff> offs,
  Worktree? worktree,
  Package at,
) {
  bool off(Package package, _HostedOff kind) =>
      package == at && offs.contains(kind);
  return (
    sdk: offs.contains(_HostedOff.sdk)
        ? .parse('${stamp.sdk.version}9')!
        : stamp.sdk,
    stamp: offs.contains(_HostedOff.stamp) ? null : stamp,
    worktree: worktree,
    there: !offs.contains(_HostedOff.handedOutGone),
    packages: {
      for (final Package package in Package.values)
        package: switch (stamp.packages[package]) {
          final StampedPackage stamped => (
            lock: off(package, .lock) ? _other(stamped.lock) : stamped.lock,
            keptLock: off(package, .keptLockGone)
                ? null
                : off(package, .keptLock)
                ? _other(stamped.lock)
                : stamped.lock,
            packageConfig: off(package, .packageConfigGone)
                ? null
                : off(package, .packageConfig)
                ? _other(stamped.packageConfig)
                : stamped.packageConfig,
          ),
          null => (lock: null, keptLock: null, packageConfig: null),
        },
    },
  );
}

void main() {
  property(
    'A git checkout stands exactly when its stamp matches the codebase\'s '
    'values, each lock\'s hash and the SDK version on PATH, the package it '
    'hands out is there, `HEAD` is the pin, no tracked file has changed '
    'and each `package_config.json` is the one it was stamped with, and is '
    'made again where any one of those is off.',
    (Draw draw) {
      final GitCodebase drawn = draw(anyGitCodebase(), label: 'codebase');
      final Map<Package, StampedPackage> packages = draw(
        anyStampedPackages,
        label: 'packages',
      );
      final SdkVersion sdk = draw(anySdkVersion, label: 'sdk');
      // At most two at once, so a draw with none off, and one with one
      // alone, are each common.
      final Set<_Off> offs = draw(
        .list(.element(_Off.values), maxLength: 2),
        label: 'offs',
      ).toSet();
      final Set<_Noise> noise = draw(
        .set(.element(_Noise.values)),
        label: 'noise',
      );
      final Package at = draw(.element(packages.keys.toList()), label: 'at');
      final Stamp stamp = stampOf(
        Git(drawn),
        _keptWhereOff(packages, at, offs),
        sdk,
      );
      final GitCodebase codebase = _edited(drawn, offs);
      expect(
        stands(Git(codebase), _survey(stamp, drawn.commit, offs, noise, at)),
        offs.isEmpty,
      );
    },
    settings: .new(runs: 400),
  );

  property(
    'A hosted checkout stands exactly when its stamp matches the codebase\'s '
    'values and the SDK version on PATH, the package it hands out is there, '
    'and each package holds the lock and '
    'the `package_config.json` it was stamped with, on its kept lock, '
    'whatever a worktree shows, and is made again where any one of those is '
    'off.',
    (Draw draw) {
      final HostedCodebase codebase = draw(
        anyHostedCodebase(),
        label: 'codebase',
      );
      final Map<Package, StampedPackage> packages = draw(
        anyStampedPackages.map(
          (Map<Package, StampedPackage> packages) => {
            for (final MapEntry<Package, StampedPackage>(:key, :value)
                in packages.entries)
              key: (
                source: LockSource.kept,
                lock: value.lock,
                packageConfig: value.packageConfig,
              ),
          },
        ),
        label: 'packages',
      );
      final SdkVersion sdk = draw(anySdkVersion, label: 'sdk');
      final Set<_HostedOff> offs = draw(
        .list(.element(_HostedOff.values), maxLength: 2),
        label: 'offs',
      ).toSet();
      final Package at = draw(.element(packages.keys.toList()), label: 'at');
      final Worktree? worktree = draw(.boolean(), label: 'there')
          ? (
              head: Commit.parse(draw(anyFullHash, label: 'head'))!,
              changed: draw(.boolean(), label: 'changed'),
            )
          : null;
      final Stamp stamp = stampOf(Hosted(codebase), packages, sdk);
      expect(
        stands(
          Hosted(_editedHosted(codebase, offs)),
          _hostedSurvey(stamp, offs, worktree, at),
        ),
        offs.isEmpty,
      );
    },
    settings: .new(runs: 400),
  );
}

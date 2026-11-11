import 'dart:convert';

import 'package:glados/glados.dart';
import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/content_hash.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/sdk_version.dart';
import 'package:muster/src/model/stamp.dart';
import 'package:muster/src/model/stamped_package.dart';
import 'package:muster/src/model/stands.dart';
import 'package:muster/src/model/survey.dart';
import 'package:muster/src/model/surveyed_package.dart';
import 'package:muster/src/model/worktree.dart';

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

/// A codebase, its stamp's packages and the SDK that resolved them, the ways
/// the survey falls off it, the changes that should not matter, and which
/// stamped package each change lands on.
typedef _Draw = ({
  GitCodebase codebase,
  Map<Package, StampedPackage> packages,
  SdkVersion sdk,
  Set<_Off> offs,
  Set<_Noise> noise,
  int at,
});

final Generator<_Draw> _draw = any.combine6(
  any.gitCodebase(),
  any.stampedPackages,
  any.sdkVersion,
  // At most two at once, so a draw with none off, and one with one alone,
  // are each common.
  any
      .listWithLengthInRange(0, 3, any.choose(_Off.values))
      .map((List<_Off> offs) => offs.toSet()),
  any.set(any.choose(_Noise.values)),
  any.intInRange(0, 2),
  (
    GitCodebase codebase,
    Map<Package, StampedPackage> packages,
    SdkVersion sdk,
    Set<_Off> offs,
    Set<_Noise> noise,
    int at,
  ) => (
    codebase: codebase,
    packages: packages,
    sdk: sdk,
    offs: offs,
    noise: noise,
    at: at,
  ),
);

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

/// The survey of a checkout stamped [stamp] that stands, then
/// fallen off by [draw]'s offs on its package [at], and changed by its noise.
Survey _survey(Stamp stamp, _Draw draw, Package at) {
  final Set<_Off> offs = draw.offs;
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
            .committed when draw.noise.contains(_Noise.committedKeptLock) =>
              _other(stamped.lock),
            .committed => null,
          },
          packageConfig: package == at && offs.contains(_Off.packageConfigGone)
              ? null
              : package == at && offs.contains(_Off.packageConfig)
              ? _other(stamped.packageConfig)
              : stamped.packageConfig,
        ),
        null when draw.noise.contains(_Noise.unstampedPackage) => (
          lock: stamp.packages[Package.root]!.lock,
          keptLock: stamp.packages[Package.root]!.lock,
          packageConfig: stamp.packages[Package.root]!.packageConfig,
        ),
        null => (lock: null, keptLock: null, packageConfig: null),
      },
  };
  final Worktree worktree = (
    head: offs.contains(_Off.head) ? _otherCommit(stamp.commit) : stamp.commit,
    changed: offs.contains(_Off.changed),
  );
  return (
    sdk: offs.contains(_Off.sdk) ? .parse('${stamp.sdk.version}9')! : stamp.sdk,
    stamp: offs.contains(_Off.stamp) ? null : stamp,
    worktree: offs.contains(_Off.worktree) ? null : worktree,
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

void main() {
  Glados(_draw, ExploreConfig(numRuns: 400)).test(
    'A git checkout stands exactly when its stamp matches the codebase\'s '
    'values, each lock\'s hash and the SDK version on PATH, `HEAD` is the '
    'pin, no tracked file has changed and each `package_config.json` is the '
    'one it was stamped with, and is made again where any one of those is '
    'off.',
    (_Draw draw) {
      final List<Package> stamped = draw.packages.keys.toList();
      final Package at = stamped[draw.at % stamped.length];
      final Stamp stamp = stampOf(
        draw.codebase,
        _keptWhereOff(draw.packages, at, draw.offs),
        draw.sdk,
      );
      final GitCodebase codebase = _edited(draw.codebase, draw.offs);
      expect(stands(codebase, _survey(stamp, draw, at)), draw.offs.isEmpty);
    },
  );
}

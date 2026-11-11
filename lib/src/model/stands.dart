import 'git_codebase.dart';
import 'package.dart';
import 'stamp.dart';
import 'stamped_package.dart';
import 'survey.dart';
import 'surveyed_package.dart';
import 'worktree.dart';

/// Whether [codebase]'s checkout stands, from what [survey] read of it
/// alone.
///
/// It stands exactly where its stamp names the codebase's URL, commit, root
/// and toolchain and the SDK on `PATH`, its `HEAD` is the commit with no
/// tracked file changed, and each package the stamp names holds the lock and
/// the package config stamped, a kept lock's source beside its manifest
/// unchanged too.
bool stands(GitCodebase codebase, Survey survey) {
  final Stamp? stamp = survey.stamp;
  final Worktree? worktree = survey.worktree;
  if (stamp == null || worktree == null) {
    return false;
  }
  return stamp.url == codebase.url &&
      stamp.commit == codebase.commit &&
      stamp.root == codebase.root &&
      stamp.toolchain == codebase.toolchain &&
      stamp.sdk == survey.sdk &&
      worktree.head == codebase.commit &&
      !worktree.changed &&
      stamp.packages.entries.every(
        (MapEntry<Package, StampedPackage> entry) =>
            _holds(entry.value, survey.packages[entry.key]),
      );
}

bool _holds(StampedPackage stamped, SurveyedPackage? surveyed) =>
    surveyed != null &&
    surveyed.lock == stamped.lock &&
    surveyed.packageConfig == stamped.packageConfig &&
    switch (stamped.source) {
      .committed => true,
      .kept => surveyed.keptLock == stamped.lock,
    };

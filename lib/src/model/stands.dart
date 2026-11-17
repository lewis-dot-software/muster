import 'codebase.dart';
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
/// It stands exactly where its stamp names the codebase as its manifest
/// does and the SDK on `PATH`, the package it hands out is there, each
/// package the stamp names holds the lock and the package config stamped, a
/// kept lock's source beside its manifest unchanged too, and, for a git
/// codebase, its `HEAD` is the commit with no tracked file changed.
bool stands(Codebase codebase, Survey survey) {
  final Stamp? stamp = survey.stamp;
  if (stamp == null) {
    return false;
  }
  return stamp.codebase == codebase &&
      stamp.sdk == survey.sdk &&
      survey.there &&
      _atPin(codebase, survey.worktree) &&
      stamp.packages.entries.every(
        (MapEntry<Package, StampedPackage> entry) =>
            _holds(entry.value, survey.packages[entry.key]),
      );
}

/// Whether [worktree] stands at [codebase]'s pin, which a hosted codebase's
/// checkout, holding no git, always does.
bool _atPin(Codebase codebase, Worktree? worktree) => switch (codebase) {
  Git(codebase: final GitCodebase git) =>
    worktree != null && worktree.head == git.commit && !worktree.changed,
  Hosted() => true,
};

bool _holds(StampedPackage stamped, SurveyedPackage? surveyed) =>
    surveyed != null &&
    surveyed.lock == stamped.lock &&
    surveyed.packageConfig == stamped.packageConfig &&
    switch (stamped.source) {
      .committed => true,
      .kept => surveyed.keptLock == stamped.lock,
    };

import 'at_commit.dart';
import 'lock_choice.dart';
import 'lock_source.dart';
import 'package.dart';

/// The lock each package [atCommit] holds resolves on: the `pubspec.lock` its
/// pin holds, as a git codebase's commit may and no hosted package does, else
/// its kept lock where it is among [kept], else none, so the first package
/// with neither is lacking.
LockChoice chooseLocks(AtCommit atCommit, Set<Package> kept) {
  final Map<Package, LockSource> locks = {};
  for (final Package package in Package.values) {
    if (!atCommit.packages.contains(package)) {
      continue;
    }
    if (atCommit.locked.contains(package)) {
      locks[package] = .committed;
    } else if (kept.contains(package)) {
      locks[package] = .kept;
    } else {
      return LockLacking(package);
    }
  }
  return LocksChosen(.unmodifiable(locks));
}

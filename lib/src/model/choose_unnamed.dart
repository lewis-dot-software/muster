import 'codebase.dart';
import 'kept_lock_path.dart';
import 'locks_directory.dart';
import 'package.dart';
import 'partial_lock_path.dart';
import 'unnamed_lock.dart';

/// What of the files [listed] in [locks], each by its name, no codebase of
/// [codebases] names, in their file names' order: every kept lock but those
/// of each codebase's packages, and every partial but theirs. A file that is
/// neither is left out.
List<UnnamedLock> chooseUnnamed(
  LocksDirectory locks,
  Iterable<String> listed,
  Iterable<Codebase> codebases,
) {
  final Set<KeptLockPath> named = {
    for (final Codebase codebase in codebases)
      for (final Package package in Package.values)
        keptLockOf(locks, codebase, package),
  };
  final Set<PartialLockPath> partials = {
    for (final KeptLockPath lock in named) .of(lock),
  };
  return [
    for (final String name in [...listed]..sort()) ...[
      if (listedKeptLock(locks, name) case final KeptLockPath lock
          when !named.contains(lock))
        UnnamedKept(lock),
      if (PartialLockPath.listed(locks, name) case final PartialLockPath partial
          when !partials.contains(partial))
        UnnamedPartial(partial),
    ],
  ];
}

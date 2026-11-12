import 'git_codebase.dart';
import 'kept_lock_path.dart';
import 'locks_directory.dart';
import 'package.dart';
import 'partial_lock_path.dart';
import 'unnamed_locks.dart';

/// What of the files [listed] in [locks], each by its name, no codebase of
/// [codebases] names: every kept lock but those of each codebase's packages,
/// and every partial but theirs. A file that is neither is left out.
UnnamedLocks chooseUnnamed(
  LocksDirectory locks,
  Iterable<String> listed,
  Iterable<GitCodebase> codebases,
) {
  final Set<KeptLockPath> named = {
    for (final GitCodebase codebase in codebases)
      for (final Package package in Package.values)
        .of(locks, codebase, package),
  };
  final Set<PartialLockPath> partials = {
    for (final KeptLockPath lock in named) .of(lock),
  };
  final List<String> names = [...listed]..sort();
  return (
    locks: [
      for (final String name in names)
        if (KeptLockPath.listed(locks, name) case final KeptLockPath lock
            when !named.contains(lock))
          lock,
    ],
    partials: [
      for (final String name in names)
        if (PartialLockPath.listed(locks, name)
            case final PartialLockPath partial when !partials.contains(partial))
          partial,
    ],
  );
}

import 'package:muster/muster.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/lock_outcome.dart';
import 'package:muster/src/model/lock_removal.dart';
import 'package:muster/src/model/package.dart';
import 'package:test/test.dart';

import 'loads.dart';

/// Matches a lock that gave an outcome to each name of [outcomes] alone, in
/// its order, each matching its matcher, and whose removals match
/// [removals], a matcher or the list it equals, none where it is left out.
Matcher lockedWith(Map<String, Matcher> outcomes, {Object? removals}) {
  TypeMatcher<Locked> locked = isA<Locked>()
      .having(
        (Locked l) => [
          for (final CodebaseName name in l.outcomes.keys) name.name,
        ],
        'names',
        outcomes.keys.toList(),
      )
      .having((Locked l) => l.removals, 'removals', removals ?? isEmpty);
  for (final MapEntry<String, Matcher>(:key, :value) in outcomes.entries) {
    locked = locked.having(
      (Locked l) => l.outcomes[CodebaseName.parse(key)!],
      key,
      value,
    );
  }
  return locked;
}

/// Matches an outcome of [LocksWritten] whose locks are [locks], in order.
Matcher wrote(List<KeptLockPath> locks) =>
    isA<LocksWritten>().having((LocksWritten w) => w.locks, 'locks', locks);

/// Matches an outcome of [LockFailed] whose failure [failure] matches.
Matcher lockFailed(Matcher failure) =>
    isA<LockFailed>().having((LockFailed f) => f.failure, 'failure', failure);

/// Matches a removal of [LockRemoved] of [lock].
Matcher removedLock(String lock) =>
    isA<LockRemoved>().having((LockRemoved r) => r.lock.path, 'lock', lock);

/// Matches a removal of [RemovalFailed] whose failure [failure] matches.
Matcher removalFailed(Matcher failure) => isA<RemovalFailed>().having(
  (RemovalFailed f) => f.failure,
  'failure',
  failure,
);

/// The kept lock of [codebase]'s [package] beside the manifest at
/// [manifest].
KeptLockPath keptOf(
  String manifest,
  GitCodebase codebase, [
  Package package = .root,
]) => .of(locksBeside(manifest), codebase, package);

import 'fetch_outcome.dart';
import 'kept_lock_path.dart';

/// What a lock gave one codebase: the kept locks it wrote, or why it
/// could not write them.
sealed class LockOutcome {
  const LockOutcome();
}

/// A codebase whose every package has a lock, the kept locks written for it
/// among them.
final class LocksWritten extends LockOutcome {
  /// The codebase whose packages lacked the kept locks at [locks], each
  /// written, in its packages' order.
  const LocksWritten(this.locks);

  /// The kept locks written, none where every package had its lock already.
  final List<KeptLockPath> locks;
}

/// A codebase whose kept locks could not be written, for [failure].
final class LockFailed extends LockOutcome {
  /// The codebase whose write failed for [failure].
  const LockFailed(this.failure);

  /// Why its kept locks could not be written.
  final ActFailure failure;
}

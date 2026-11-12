import 'fetch_outcome.dart';
import 'kept_lock_path.dart';

/// What `muster lock` gave a lock no codebase of its manifest names: its
/// removal, or why it could not be removed.
sealed class LockRemoval {
  const LockRemoval();
}

/// A kept lock no codebase names, removed.
final class LockRemoved extends LockRemoval {
  /// The removal of [lock].
  const LockRemoved(this.lock);

  /// The lock removed.
  final KeptLockPath lock;
}

/// A removal that failed, or a locks directory that could not be read for
/// what to remove.
final class RemovalFailed extends LockRemoval {
  /// The removal that failed for [failure].
  const RemovalFailed(this.failure);

  /// The file act that failed.
  final StoreFailed failure;
}

import 'kept_lock_path.dart';
import 'partial_lock_path.dart';

/// A file in a locks directory that no codebase of its manifest names: a
/// kept lock, or the partial of one.
sealed class UnnamedLock {
  const UnnamedLock();
}

/// A kept lock no codebase names.
final class UnnamedKept extends UnnamedLock {
  /// The kept [lock], which no codebase names.
  const UnnamedKept(this.lock);

  /// The kept lock.
  final KeptLockPath lock;
}

/// The partial of a kept lock no codebase names, left by a write cut short.
final class UnnamedPartial extends UnnamedLock {
  /// The [partial], which no codebase names.
  const UnnamedPartial(this.partial);

  /// The partial.
  final PartialLockPath partial;
}

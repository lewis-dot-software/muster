import '../model/codebase_name.dart';
import '../model/load_refusal.dart';
import '../model/lock_outcome.dart';
import '../model/lock_removal.dart';

/// What a lock gave: each codebase's kept locks written and each lock no
/// codebase names removed, or why it refused before any write.
sealed class Locking {
  const Locking();
}

/// A lock whose manifests were read, every codebase they name given its
/// outcome.
final class Locked extends Locking {
  /// The lock that gave [outcomes] and [removals].
  const Locked(this.outcomes, this.removals);

  /// Each codebase's outcome, keyed by its name, in the manifests' order,
  /// each manifest's codebases in its own.
  final Map<CodebaseName, LockOutcome> outcomes;

  /// Each kept lock no codebase of its manifest names, removed or failing
  /// to be, each partial of a write cut short that failed to be removed,
  /// and each locks directory that could not be read, in the manifests'
  /// order, each manifest's in its file names' order.
  final List<LockRemoval> removals;
}

/// A lock refused before any process or file write, as a load refuses.
final class LockRefused extends Locking {
  /// The lock refused for [reason].
  const LockRefused(this.reason);

  /// Why the lock refused.
  final LoadRefusal reason;
}

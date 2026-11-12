import 'kept_lock_path.dart';
import 'partial_lock_path.dart';

/// What a locks directory holds that no codebase of its manifest names: the
/// kept [locks], and the [partials] of kept locks, each in its file name's
/// order.
typedef UnnamedLocks = ({
  List<KeptLockPath> locks,
  List<PartialLockPath> partials,
});

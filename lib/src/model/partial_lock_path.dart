import 'kept_lock_path.dart';
import 'locks_directory.dart';

/// The file a kept lock is written to before it is moved into place, so a
/// write cut short never leaves a lock that is part of one.
extension type const PartialLockPath._(String path) {
  /// The partial of [lock]: its path with `.partial` after it.
  static PartialLockPath of(KeptLockPath lock) => ._('${lock.path}$_suffix');

  /// The partial named [name] in [locks], or null where [name] is no kept
  /// lock's file name with `.partial` after it.
  static PartialLockPath? listed(LocksDirectory locks, String name) =>
      name.endsWith(_suffix) &&
          KeptLockPath.listed(
                locks,
                name.substring(0, name.length - _suffix.length),
              ) !=
              null
      ? ._(locks.os.paths.join(locks.path, name))
      : null;
}

const String _suffix = '.partial';

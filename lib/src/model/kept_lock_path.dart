import 'git_codebase.dart';
import 'lock_key.dart';
import 'locks_directory.dart';
import 'package.dart';

/// The file of a kept lock, a lock muster keeps beside a manifest for a
/// package whose commit holds none.
extension type const KeptLockPath._(String path) {
  /// The kept lock of [codebase]'s [package] in [locks]:
  /// `<name>-<key>.lock`, with `.example` before `.lock` for the example, the
  /// key the codebase's [LockKey].
  static KeptLockPath of(
    LocksDirectory locks,
    GitCodebase codebase,
    Package package,
  ) {
    final String suffix = switch (package) {
      .root => '',
      .example => '.example',
    };
    return ._(
      locks.os.paths.join(
        locks.path,
        '${codebase.name.name}-${LockKey.of(codebase).hex}$suffix$_extension',
      ),
    );
  }

  /// The lock named [name] in [locks], every file there whose name ends
  /// `.lock` after a stem of its own being one, or null where [name] is
  /// none.
  static KeptLockPath? listed(LocksDirectory locks, String name) =>
      name.length > _extension.length && name.endsWith(_extension)
      ? ._(locks.os.paths.join(locks.path, name))
      : null;
}

const String _extension = '.lock';

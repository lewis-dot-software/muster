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
        '${codebase.name.name}-${LockKey.of(codebase).hex}$suffix.lock',
      ),
    );
  }
}

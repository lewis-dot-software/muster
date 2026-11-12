import '../model/os.dart';
import 'kernel.dart';
import 'libc.dart';

/// What takes a system's claims: the kernel's lock each hold takes, and the
/// calls it takes it through.
sealed class Locker {
  const Locker();

  /// The locker of a system of [os] that `dart:io` names [system], its C
  /// library bound where it is a POSIX system, or null where muster knows no
  /// C library of it.
  static Locker? of(Os os, String system) => switch (os) {
    .posix => switch (Kernel.named(system)) {
      final Kernel kernel => FlockLocker(.new(kernel, .process())),
      null => null,
    },
    .windows => const LockFileExLocker(),
  };
}

/// `flock`'s lock, taken through [libc].
final class FlockLocker extends Locker {
  /// The locker that takes `flock`'s lock through [libc].
  const FlockLocker(this.libc);

  /// The C library the lock is taken through.
  final Libc libc;
}

/// `LockFileEx`'s lock, taken through `dart:io`.
final class LockFileExLocker extends Locker {
  /// The locker that takes `LockFileEx`'s lock.
  const LockFileExLocker();
}

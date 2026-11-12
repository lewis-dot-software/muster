/// The kernel of a POSIX system muster takes claims on, which sets where its
/// C library keeps `errno` and how it spells two constants.
enum Kernel {
  /// macOS's.
  darwin(errno: '__error', readOnlyCloseOnExec: 0x1000000, wouldBlock: 35),

  /// Linux's.
  linux(
    errno: '__errno_location',
    readOnlyCloseOnExec: 0x80000,
    wouldBlock: 11,
  );

  const Kernel({
    required this.errno,
    required this.readOnlyCloseOnExec,
    required this.wouldBlock,
  });

  /// The kernel of the system `dart:io` names [system], or null where muster
  /// knows no C library of it.
  static Kernel? named(String system) => switch (system) {
    'macos' => .darwin,
    'linux' => .linux,
    _ => null,
  };

  /// The function that gives the calling thread's `errno`'s address.
  final String errno;

  /// `O_RDONLY | O_CLOEXEC`, `O_RDONLY` being 0 on both.
  final int readOnlyCloseOnExec;

  /// `EWOULDBLOCK`, which `flock` fails with where another open holds the
  /// lock.
  final int wouldBlock;
}

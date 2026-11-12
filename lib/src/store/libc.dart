import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The C library a POSIX hold calls, which differs between systems in where
/// it keeps `errno` and in how it spells two constants.
enum _Kernel {
  darwin(errno: '__error', readOnlyCloseOnExec: 0x1000000, wouldBlock: 35),
  linux(
    errno: '__errno_location',
    readOnlyCloseOnExec: 0x80000,
    wouldBlock: 11,
  );

  const _Kernel({
    required this.errno,
    required this.readOnlyCloseOnExec,
    required this.wouldBlock,
  });

  /// The function that gives the calling thread's `errno`'s address.
  final String errno;

  /// `O_RDONLY | O_CLOEXEC`, `O_RDONLY` being 0 on both.
  final int readOnlyCloseOnExec;

  /// `EWOULDBLOCK`, which `flock` fails with where another open holds the
  /// lock.
  final int wouldBlock;
}

/// The C library's calls a claim's hold makes on a POSIX system, each bound once, all together,
/// so the first take binds none between a call and its read of `errno`.
final class Libc {
  Libc._(_Kernel kernel, DynamicLibrary libc)
    : wouldBlock = kernel.wouldBlock,
      readOnlyCloseOnExec = kernel.readOnlyCloseOnExec,
      // `open` takes a variadic mode, passed only with `O_CREAT`, so its
      // fixed arguments alone are called as they would be on a function of
      // two.
      open = libc
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Int32),
            int Function(Pointer<Utf8>, int)
          >('open', isLeaf: true),
      flock = libc
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'flock',
            isLeaf: true,
          ),
      close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'close',
        isLeaf: true,
      ),
      _errnoAt = libc
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            kernel.errno,
            isLeaf: true,
          ),
      _strerror = libc
          .lookupFunction<
            Pointer<Utf8> Function(Int32),
            Pointer<Utf8> Function(int)
          >('strerror'),
      // `close` takes the descriptor where a finalizer passes its token, a
      // word in the first argument's register.
      closer = .new(libc.lookup<NativeFinalizerFunction>('close'));

  /// `EWOULDBLOCK`.
  final int wouldBlock;

  /// `O_RDONLY | O_CLOEXEC`.
  final int readOnlyCloseOnExec;

  /// `open`, a leaf call, so no VM work runs between it and the read of
  /// `errno` after it, as with [flock].
  final int Function(Pointer<Utf8>, int) open;

  /// `flock`, a leaf call.
  final int Function(int, int) flock;

  /// `close`.
  final int Function(int) close;

  /// The finalizer that closes a descriptor no hold released.
  final NativeFinalizer closer;

  final Pointer<Int32> Function() _errnoAt;

  final Pointer<Utf8> Function(int) _strerror;

  /// What the last call on this thread left in `errno`.
  int get errno => _errnoAt().value;

  /// What the system says of [errno].
  String message(int errno) => _strerror(errno).toDartString();
}

/// The C library of the POSIX system muster runs on, bound when the first
/// claim is taken there.
final Libc libc = ._(switch (Platform.operatingSystem) {
  'macos' => .darwin,
  'linux' => .linux,
  final String system => throw UnsupportedError(
    'a claim on $system has no C library muster knows',
  ),
}, .process());

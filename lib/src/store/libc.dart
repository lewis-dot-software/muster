import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'kernel.dart';

/// The C library's calls a claim's hold makes on a POSIX system, each bound
/// once, all together, so no take binds one between a call and its read of
/// `errno`.
interface class Libc {
  /// The calls of [libc], the C library of a system of [kernel].
  Libc(Kernel kernel, DynamicLibrary libc)
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
          >('strerror');

  /// `EWOULDBLOCK`.
  final int wouldBlock;

  /// `O_RDONLY | O_CLOEXEC`.
  final int readOnlyCloseOnExec;

  /// `open`, a leaf call, so no VM work runs inside it, as with [flock].
  final int Function(Pointer<Utf8>, int) open;

  /// `flock`, a leaf call.
  final int Function(int, int) flock;

  /// `close`.
  final int Function(int) close;

  final Pointer<Int32> Function() _errnoAt;

  final Pointer<Utf8> Function(int) _strerror;

  /// What the last call on this thread left in `errno`, which the VM's own
  /// work on the thread since that call may have overwritten.
  int get errno => _errnoAt().value;

  /// What the system says of [errno].
  String message(int errno) => _strerror(errno).toDartString();
}

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:muster/src/store/libc.dart';

/// The C library [_libc] with its `flock` failing every call, leaving
/// [errno] in `errno` though it took [_libc]'s lock, and its every other call
/// [_libc]'s own.
final class FailingFlock implements Libc {
  /// The C library [_libc] whose `flock` fails with [errno].
  FailingFlock(this._libc, this.errno);

  final Libc _libc;

  @override
  final int errno;

  @override
  int get wouldBlock => _libc.wouldBlock;

  @override
  int get readOnlyCloseOnExec => _libc.readOnlyCloseOnExec;

  @override
  int Function(Pointer<Utf8>, int) get open => _libc.open;

  @override
  int Function(int, int) get flock => (int descriptor, int operation) {
    _libc.flock(descriptor, operation);
    return -1;
  };

  @override
  int Function(int) get close => _libc.close;

  @override
  NativeFinalizer get closer => _libc.closer;

  @override
  String message(int errno) => _libc.message(errno);
}

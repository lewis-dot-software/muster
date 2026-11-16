import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:muster/src/store/libc.dart';

/// The C library [_libc] with its `flock` failing its first [_failing] calls,
/// or every call where none is given, each leaving [_errno] in `errno` though
/// it took [_libc]'s lock where that was free, and its every other call
/// [_libc]'s own.
final class FailingFlock implements Libc {
  /// The C library [_libc] whose `flock` fails with [_errno], its first
  /// [_failing] calls alone where that is given.
  FailingFlock(this._libc, this._errno, [this._failing]);

  final Libc _libc;

  final int _errno;

  /// How many calls are left to fail, null where every call fails.
  int? _failing;

  /// Whether the last call of `flock` was made to fail.
  bool _failed = false;

  @override
  int get errno => _failed ? _errno : _libc.errno;

  @override
  int get wouldBlock => _libc.wouldBlock;

  @override
  int get readOnlyCloseOnExec => _libc.readOnlyCloseOnExec;

  @override
  int Function(Pointer<Utf8>, int) get open => _libc.open;

  @override
  int Function(int, int) get flock => (int descriptor, int operation) {
    final int took = _libc.flock(descriptor, operation);
    switch (_failing) {
      case null:
        _failed = true;
      case 0:
        _failed = false;
      case final int left:
        _failing = left - 1;
        _failed = true;
    }
    return _failed ? -1 : took;
  };

  @override
  int Function(int) get close => _libc.close;

  @override
  String message(int errno) => _libc.message(errno);
}

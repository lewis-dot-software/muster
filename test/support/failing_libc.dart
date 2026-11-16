import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:muster/src/store/libc.dart';

import 'failing.dart';

/// The C library [_libc] with its `open` and its `flock` failing where each
/// is given a [Failing], though each call is made on [_libc], so a file that
/// opens is opened and closed again and a lock that is free is taken, and its
/// every other call [_libc]'s own.
final class FailingLibc implements Libc {
  /// The C library [_libc] whose `open` fails as [_open] fails, where that is
  /// given, and whose `flock` fails as [_flock] fails, where that is given.
  FailingLibc(this._libc, {this._open, this._flock});

  final Libc _libc;

  final Failing? _open;

  final Failing? _flock;

  /// What the last call made to fail left in `errno`, null where the last
  /// call was [_libc]'s own.
  int? _errno;

  @override
  int get errno => _errno ?? _libc.errno;

  @override
  int get wouldBlock => _libc.wouldBlock;

  @override
  int get readOnlyCloseOnExec => _libc.readOnlyCloseOnExec;

  @override
  int Function(Pointer<Utf8>, int) get open => (Pointer<Utf8> path, int flags) {
    final int descriptor = _libc.open(path, flags);
    if (_failed(_open)) {
      if (descriptor >= 0) {
        _libc.close(descriptor);
      }
      return -1;
    }
    return descriptor;
  };

  @override
  int Function(int, int) get flock => (int descriptor, int operation) {
    final int took = _libc.flock(descriptor, operation);
    return _failed(_flock) ? -1 : took;
  };

  @override
  int Function(int) get close => _libc.close;

  @override
  String message(int errno) => _libc.message(errno);

  /// Whether the call made now fails as [failing] fails, its `errno` left.
  bool _failed(Failing? failing) {
    if (failing != null && failing.fails) {
      _errno = failing.errno;
      return true;
    }
    _errno = null;
    return false;
  }
}

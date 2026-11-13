import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../model/claim_path.dart';
import '../model/fetch_outcome.dart';
import 'file_act.dart';
import 'libc.dart';
import 'locker.dart';
import 'store_fault.dart';

/// A claim held: the kernel's lock on the claim's file, taken through an open
/// of the file this hold made, so it shuts out every other open of the file,
/// an isolate's of the same process as much as another process's.
///
/// The kernel lets the lock go when that open closes: at [release], at the
/// end of the isolate group that took it, or at the end of its process,
/// whether it exits or is killed. So a hold its holder never releases never
/// blocks a later one, with no holder named and nothing to take over.
sealed class Hold {
  const Hold();

  /// The claim at [claim] held by [locker], or null where another open of its file holds
  /// it. The file must be there.
  ///
  /// Throws a [StoreFault] of [StoreFailed] where the file cannot be opened
  /// or locked.
  static Future<Hold?> take(ClaimPath claim, Locker locker) async =>
      switch (locker) {
        FlockLocker(:final Libc libc) => _Flock.take(claim, libc),
        LockFileExLocker() => await _LockFileEx.take(claim),
      };

  /// Lets the claim go.
  Future<void> release();
}

/// A hold on a POSIX system: `flock`'s lock, which belongs to the open file,
/// where `fcntl`'s, the one `dart:io` takes, belongs to the whole process and
/// shuts out no isolate of it.
///
/// The file is opened close-on-exec, so a process any isolate starts while it
/// is open carries the lock from its fork to its exec alone, and [_closer]
/// closes it once the hold is collected where it is never released, at the
/// end of the isolate group at the latest.
final class _Flock extends Hold implements Finalizable {
  _Flock._(this._libc, this._descriptor) {
    _closer.attach(this, .fromAddress(_descriptor), detach: this);
  }

  /// The finalizer that closes a descriptor no hold released, static since a
  /// native finalizer runs only while it is itself reachable, and a hold
  /// collected unreleased may take every object of its load with it.
  // `close` takes the descriptor where a finalizer passes its token, a word
  // in the first argument's register.
  static final NativeFinalizer _closer = .new(
    Native.addressOf<NativeFunction<Int32 Function(Int32)>>(_closeNative)
        .cast(),
  );

  /// `close`, as the process binds it.
  @Native<Int32 Function(Int32)>(symbol: 'close', isLeaf: true)
  external static int _closeNative(int descriptor);

  final Libc _libc;

  final int _descriptor;

  static Hold? take(ClaimPath claim, Libc libc) {
    final Pointer<Utf8> path = claim.path.toNativeUtf8();
    final int descriptor = libc.open(path, libc.readOnlyCloseOnExec);
    final int opening = libc.errno;
    malloc.free(path);
    if (descriptor < 0) {
      throw StoreFault(StoreFailed(claim.path, libc.message(opening)));
    }
    final _Flock hold = ._(libc, descriptor);
    if (libc.flock(descriptor, _exclusive | _nonBlocking) == 0) {
      return hold;
    }
    final int locking = libc.errno;
    hold._close();
    if (locking == libc.wouldBlock) {
      return null;
    }
    throw StoreFault(StoreFailed(claim.path, libc.message(locking)));
  }

  @override
  Future<void> release() async => _close();

  void _close() {
    _closer.detach(this);
    _libc.close(_descriptor);
  }
}

/// A hold on Windows: `dart:io`'s lock, which is `LockFileEx` there and
/// belongs to the open handle, closed at the end of the isolate group where
/// the hold is never released.
final class _LockFileEx extends Hold {
  _LockFileEx._(this._file);

  final RandomAccessFile _file;

  static Future<Hold?> take(ClaimPath claim) async {
    final RandomAccessFile file = await fileAct(
      claim.path,
      () => File(claim.path).open(mode: .append),
    );
    try {
      await file.lock(.exclusive);
      return _LockFileEx._(file);
    } on FileSystemException catch (e) {
      await fileAct(claim.path, file.close);
      if (e.osError?.errorCode == _lockViolation) {
        return null;
      }
      throw StoreFault(
        StoreFailed(e.path ?? claim.path, e.osError?.message ?? e.message),
      );
    }
  }

  @override
  Future<void> release() => fileAct(_file.path, _file.close);
}

/// `LOCK_EX`, on every POSIX system.
const int _exclusive = 2;

/// `LOCK_NB`, on every POSIX system.
const int _nonBlocking = 4;

/// `ERROR_LOCK_VIOLATION`, which `LockFileEx` fails with where another handle
/// holds the lock.
const int _lockViolation = 33;

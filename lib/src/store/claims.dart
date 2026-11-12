import 'dart:io';

import '../model/claim_path.dart';
import '../model/fetch_outcome.dart';
import '../model/os.dart';
import 'file_act.dart';
import 'hold.dart';
import 'store_fault.dart';

/// The claims a load takes on the clones and checkouts it acts on, each held
/// while it acts and let go after, so no two loads act on one at once,
/// whether they are isolates of one process or separate processes.
class Claims {
  /// The claims on a system of [_os], [_waited] run each time a claim is
  /// found held, before it is tried again.
  Claims(this._os, [this._waited = _pause]);

  final Os _os;

  final Future<void> Function() _waited;

  /// [act] run holding the claim at [claim], its file made where none is
  /// there, taken once no other hold has it and let go once [act] is done,
  /// whether it returned or threw.
  ///
  /// Throws a [StoreFault] of [StoreFailed] where the claim's file cannot be
  /// made, opened or locked.
  Future<T> holding<T>(ClaimPath claim, Future<T> Function() act) async {
    await _made(claim);
    final Hold hold = await _take(claim);
    try {
      return await act();
    } finally {
      await hold.release();
    }
  }

  /// Whether [act] ran: run holding the claim at [claim], its file made
  /// where none is there, where no other hold has it, and let go once [act]
  /// is done, whether it returned or threw. A claim another hold has is
  /// never waited on.
  ///
  /// Throws a [StoreFault] of [StoreFailed] where the claim's file cannot be
  /// made, opened or locked.
  Future<bool> holdingIfFree(
    ClaimPath claim,
    Future<void> Function() act,
  ) async {
    await _made(claim);
    final Hold? hold = await Hold.take(claim, _os);
    if (hold == null) {
      return false;
    }
    try {
      await act();
      return true;
    } finally {
      await hold.release();
    }
  }

  Future<void> _made(ClaimPath claim) =>
      fileAct(claim.path, () => File(claim.path).create(recursive: true));

  Future<Hold> _take(ClaimPath claim) async {
    while (true) {
      if (await Hold.take(claim, _os) case final Hold hold) {
        return hold;
      }
      await _waited();
    }
  }
}

/// The wait between two tries of a claim another hold has.
Future<void> _pause() => Future<void>.delayed(const Duration(milliseconds: 50));

import 'dart:async';

import 'package:muster/src/store/claims.dart';

import 'locker.dart';

/// Claims whose every wait on a claim found held completes [waited], the
/// first time, then gives the event loop a turn before the claim is tried
/// again.
Claims waitingInto(Completer<void> waited) => .new(testLocker, () async {
  if (!waited.isCompleted) {
    waited.complete();
  }
  await Future<void>.delayed(.zero);
});

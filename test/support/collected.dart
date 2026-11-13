import 'dart:developer';

/// Garbage made until the VM has collected every object that was unreachable
/// when this was called and scheduled its finalizers, then a turn of the event
/// loop for them to run.
Future<void> collected() async {
  // The barrier is passed twice, since a collection already marking when this
  // is called may have found those objects still reachable, and moves it once
  // without collecting them.
  final int barrier = reachabilityBarrier + 1;
  // Lists this large are made in the old space, so the garbage reaches the
  // collection that moves the barrier, and the last few are kept, so none is
  // made away with unmade.
  final List<List<int>> made = [];
  while (reachabilityBarrier <= barrier) {
    made.add(.filled(1 << 16, made.length));
    if (made.length == 64) {
      made.clear();
    }
  }
  await Future<void>(() {});
}

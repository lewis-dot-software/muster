/// What a contender contends for.
enum Contention {
  /// One checkout's claim, held bare until the test says to release it.
  hold,

  /// A load of the manifests it is given.
  load,

  /// One checkout's claim taken and let go, then tried once more, in a
  /// process that starts no other, so no fork carries the claim.
  relet,
}

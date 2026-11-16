/// What an abandoning contender keeps of each claim it never releases.
enum Keeping {
  /// Nothing, so the claims that took it and their locker are collected with
  /// its hold.
  nothing,

  /// The claims that took it, so they stay reachable while its hold is
  /// collected.
  claims,
}

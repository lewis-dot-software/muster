/// How a git checkout is made again at its pin.
enum CheckoutStep {
  /// The worktree moved to the pin by a checkout and a clean.
  move,

  /// Whatever stands there removed, and a worktree of the clone added
  /// afresh.
  replace,
}

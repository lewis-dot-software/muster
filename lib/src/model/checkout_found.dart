/// What stands at a checkout's directory before it is made again.
enum CheckoutFound {
  /// No directory.
  nothing,

  /// A worktree of the clone of its codebase's URL.
  worktreeOfClone,

  /// Any other directory, one that is no worktree or a worktree of another
  /// repo among them.
  other,
}

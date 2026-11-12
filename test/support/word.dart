/// What a test tells its contender.
enum Word {
  /// Run the paused command.
  go,

  /// Fail the paused command, as one that exited 1.
  fail,

  /// Let the bare claim go.
  release,

  /// End.
  exit,
}

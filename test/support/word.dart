/// What a test tells its contender.
enum Word {
  /// Let the paused command go on: run, where it is held before its run, or
  /// hand back its result, where it is held once it has run.
  go,

  /// Fail the paused command, as one that exited 1, in place of its run or
  /// its result.
  fail,

  /// Let the bare claim go.
  release,

  /// End.
  exit,
}

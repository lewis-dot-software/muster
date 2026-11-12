// The words a contender and its test say to each other on their line.

/// What a contender contends for.
enum Contention {
  /// One checkout's claim, held bare until the test says to release it.
  hold,

  /// A load of the manifests it is given.
  load,
}

/// What a contender tells its test.
enum Said {
  /// The claim it holds bare is taken.
  held,

  /// A command it runs, followed by the command as JSON.
  ran,

  /// The command its pause names is held until the test's word.
  paused,

  /// One of its claims was found held, the first time.
  waiting,

  /// Its load is done, followed by each codebase's outcome as JSON.
  done,
}

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

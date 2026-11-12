// The words a contender and its test say to each other on their line.

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

/// How a reletting contender takes its claim first.
enum Take {
  /// By `holding`, which waits on a claim found held.
  waiting,

  /// By `holdingIfFree`, which tries it once.
  once,
}

/// What the act a reletting contender holds its claim for does.
enum Act {
  /// Returns.
  returns,

  /// Throws a `FormatException`.
  throws,
}

/// What a contender tells its test.
enum Said {
  /// The claim it holds bare is taken.
  held,

  /// Its claim, let go, was taken again where it was tried once more.
  free,

  /// Its claim, let go, was found held where it was tried once more.
  kept,

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

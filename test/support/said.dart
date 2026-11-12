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

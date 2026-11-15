/// The code the `muster` command exits with.
enum ExitCode {
  /// Every codebase fetched, or every kept lock lacking written and every
  /// lock no codebase names removed. `--help` exits with it too.
  done(0),

  /// A codebase not fetched, a kept lock not written, or a lock not removed,
  /// each named in its row.
  failed(1),

  /// A run refused before any process or file write: a manifest that does
  /// not hold, none at all, no working directory, no cache or no claim.
  refused(2),

  /// A command line muster does not take, the usage written beside it.
  usage(64);

  const ExitCode(this.code);

  /// The process's exit code.
  final int code;
}

import 'command.dart';
import 'commit.dart';
import 'executable.dart';
import 'git_url.dart';

/// Why a codebase could not be brought to its pin.
sealed class FetchFailure {
  const FetchFailure();
}

/// A command that ran and exited with a code it should not have.
final class CommandFailed extends FetchFailure {
  /// The failure of [command], which exited [exitCode], writing [stdout] and
  /// [stderr].
  const CommandFailed(this.command, this.exitCode, this.stdout, this.stderr);

  /// The command that failed.
  final Command command;

  /// The code it exited with.
  final int exitCode;

  /// What it wrote to its standard output.
  final String stdout;

  /// What it wrote to its standard error.
  final String stderr;
}

/// An executable that could not start.
final class Unstartable extends FetchFailure {
  /// The failure of [executable] to start.
  const Unstartable(this.executable);

  /// The executable that could not start.
  final Executable executable;
}

/// A file act that failed.
final class StoreFailed extends FetchFailure {
  /// The failure of an act on [path], for the [reason] the system gave.
  const StoreFailed(this.path, this.reason);

  /// The path the act failed on, as the system reported it.
  final String path;

  /// What the system said.
  final String reason;
}

/// A pin's commit that its URL's fetch did not bring.
final class PinMissing extends FetchFailure {
  /// The failure of [url]'s fetch to bring [commit].
  const PinMissing(this.url, this.commit);

  /// The URL fetched.
  final GitUrl url;

  /// The commit, on none of its branches or tags.
  final Commit commit;
}

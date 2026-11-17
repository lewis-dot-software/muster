import 'command.dart';
import 'commit.dart';
import 'example.dart';
import 'executable.dart';
import 'git_url.dart';
import 'kept_lock_path.dart';
import 'package_path.dart';
import 'sdk_version.dart';

/// What a load gave one codebase: its package at its pin, resolved, or why
/// it could not be brought there.
sealed class FetchOutcome {
  const FetchOutcome();
}

/// A codebase brought to its pin and resolved.
final class Fetched extends FetchOutcome {
  /// The codebase whose [package], the one to hand a tool, was resolved by
  /// [sdk], beside what was made of its [example].
  const Fetched(this.package, this.example, this.sdk);

  /// The package to hand a tool, inside the codebase's checkout.
  final PackagePath package;

  /// The package's example: none, resolved, or left unresolved and why.
  final Example example;

  /// The version of the SDK that resolved it.
  final SdkVersion sdk;
}

/// Why a codebase could not be brought to its pin.
sealed class FetchFailure extends FetchOutcome {
  const FetchFailure();
}

/// A failure of an act on the world outside muster: a command, an
/// executable's start, a file act, or a fetch that did not bring its commit.
sealed class ActFailure {}

/// A command that ran and exited with a code it should not have, or wrote
/// what muster could not read.
final class CommandFailed extends FetchFailure implements ActFailure {
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
final class Unstartable extends FetchFailure implements ActFailure {
  /// The failure of [executable] to start.
  const Unstartable(this.executable);

  /// The executable that could not start.
  final Executable executable;
}

/// A file act that failed.
final class StoreFailed extends FetchFailure implements ActFailure {
  /// The failure of an act on [path], for the [reason] the system gave.
  const StoreFailed(this.path, this.reason);

  /// The path the act failed on, as the system reported it.
  final String path;

  /// What the system said.
  final String reason;
}

/// A pin's commit that its URL's fetch did not bring.
final class PinMissing extends FetchFailure implements ActFailure {
  /// The failure of [url]'s fetch to bring [commit].
  const PinMissing(this.url, this.commit);

  /// The URL fetched.
  final GitUrl url;

  /// The commit, on none of its branches or tags.
  final Commit commit;
}

/// A package that has no lock to resolve on: its pin holds none, as no
/// hosted codebase's does, and its kept lock is not there.
final class Unlocked extends FetchFailure {
  /// The failure of a package whose kept lock, at [lock], is not there.
  const Unlocked(this.lock);

  /// The kept lock the package needs.
  final KeptLockPath lock;
}

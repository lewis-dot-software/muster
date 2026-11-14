import 'package:muster/muster.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/consumer_root.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/package_path.dart';

/// A case of [FetchOutcome], each named once in [of], so a case the type
/// gains fails the build until it is named here.
enum OutcomeCase {
  /// [Fetched].
  fetched,

  /// [Unlocked].
  unlocked,

  /// [CommandFailed].
  commandFailed,

  /// [Unstartable].
  unstartable,

  /// [StoreFailed].
  storeFailed,

  /// [PinMissing].
  pinMissing;

  /// The case of [outcome].
  static OutcomeCase of(FetchOutcome outcome) => switch (outcome) {
    Fetched() => .fetched,
    Unlocked() => .unlocked,
    CommandFailed() => .commandFailed,
    Unstartable() => .unstartable,
    StoreFailed() => .storeFailed,
    PinMissing() => .pinMissing,
  };

  /// An outcome of this case for [codebase], its checkout under `/consumer`
  /// on SDK `3.13.0` where it is [Fetched], its kept lock that of [package]
  /// beside `/consumer/muster.yaml` where it is [Unlocked], and carrying
  /// [exitCode], [output] and [executable] where it carries them.
  FetchOutcome outcome(
    GitCodebase codebase, {
    required int exitCode,
    required String output,
    required Package package,
    required Executable executable,
  }) => switch (this) {
    .fetched => Fetched(
      packageIn(.of(_root, codebase.name), codebase.root, .root),
      .parse('3.13.0')!,
    ),
    .unlocked => Unlocked(keptLockOf(_locks, Git(codebase), package)),
    .commandFailed => CommandFailed(
      (executable: executable, arguments: ['clone', codebase.url.url]),
      exitCode,
      output,
      output,
    ),
    .unstartable => Unstartable(executable),
    .storeFailed => StoreFailed('/consumer/${codebase.name.name}', output),
    .pinMissing => PinMissing(codebase.url, codebase.commit),
  };
}

/// The consumer's root every [Fetched] outcome's checkout stands under.
final ConsumerRoot _root = .new('/consumer', .posix);

/// The locks every [Unlocked] outcome's kept lock stands in.
final LocksDirectory _locks = .beside(.parse('/consumer/muster.yaml', .posix)!);

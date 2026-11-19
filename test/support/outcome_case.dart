import 'package:muster/muster.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/package_path.dart';

import 'example_case.dart';
import 'loads.dart';

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

  /// An outcome of this case for [codebase], its checkout under [under] on
  /// SDK `3.13.0` with an example of [example] where it is [Fetched], the
  /// example left unresolved for the path [outside] where it is so, its kept
  /// lock that of [package] beside `<under>/muster.yaml` where it is
  /// [Unlocked], its path under [under] where it is [StoreFailed], and
  /// carrying [exitCode], [output] and [executable] where it carries them.
  FetchOutcome outcome(
    GitCodebase codebase, {
    required int exitCode,
    required String output,
    required Package package,
    required Executable executable,
    String under = '/consumer',
    ExampleCase example = .none,
    String outside = '../outside',
  }) {
    final ConsumerRoot root = .new(under, .posix);
    return switch (this) {
      .fetched => Fetched(
        packageIn(.of(root, codebase.name), codebase.root, .root),
        example.example(root, codebase, outside),
        .parse('3.13.0')!,
      ),
      .unlocked => Unlocked(
        keptLockOf(locksBeside('$under/muster.yaml'), Git(codebase), package),
      ),
      .commandFailed => CommandFailed(
        (executable: executable, arguments: ['clone', codebase.url.url]),
        exitCode,
        output,
        output,
      ),
      .unstartable => Unstartable(executable),
      .storeFailed => StoreFailed('$under/${codebase.name.name}', output),
      .pinMissing => PinMissing(codebase.url, codebase.commit),
    };
  }
}

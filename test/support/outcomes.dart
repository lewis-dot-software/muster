import 'package:glados/glados.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/consumer_root.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/package.dart';

import 'manifests.dart';

/// A case of [FetchOutcome].
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
  pinMissing,
}

/// The consumer's root every drawn outcome's checkout stands under.
final ConsumerRoot _root = .new('/consumer', .posix);

/// The locks every drawn kept lock stands in.
final LocksDirectory _locks = .beside(.parse('/consumer/muster.yaml', .posix)!);

/// An outcome of [kind] for [codebase], every value it carries drawn from
/// the codebase, and [exitCode] and [output] where it carries them.
FetchOutcome outcomeOf(
  OutcomeCase kind,
  GitCodebase codebase,
  int exitCode,
  String output,
) => switch (kind) {
  .fetched => Fetched(
    .of(CheckoutPath.of(_root, codebase.name), codebase.root, .root),
    .parse('3.13.0')!,
  ),
  .unlocked => Unlocked(.of(_locks, codebase, Package.values[exitCode % 2])),
  .commandFailed => CommandFailed(
    (executable: .git, arguments: ['clone', codebase.url.url]),
    exitCode,
    output,
    output,
  ),
  .unstartable => Unstartable(Executable.values[exitCode % 3]),
  .storeFailed => StoreFailed('/consumer/${codebase.name.name}', output),
  .pinMissing => PinMissing(codebase.url, codebase.commit),
};

/// A refusal of each case of [LoadRefusal], of each [ManifestRefusal] and
/// [Written] a manifest's carries, and of no cache on each [Os].
final List<LoadRefusal> everyRefusal = [
  const NoManifest(),
  const NotManifestName('/consumer/muster.yml'),
  ManifestMissing(_manifest('missing')),
  ManifestUnreadable(_manifest('unreadable'), 'Permission denied'),
  ManifestInvalid(
    _manifest('not_yaml'),
    const NotYaml('line 1, column 2: Expected node content.'),
  ),
  ManifestInvalid(_manifest('unknown'), UnknownKey(pathOf(['depth']))),
  ManifestInvalid(_manifest('missing_key'), MissingKey(pathOf(['git']))),
  for (final Written written in const [
    WrittenText('go'),
    WrittenList(),
    WrittenMapping(),
    WrittenNothing(),
  ])
    ManifestInvalid(
      _manifest('bad_value'),
      BadValue(pathOf(['codebases', 'app', 'toolchain']), .toolchain, written),
    ),
  ManifestInvalid(
    _manifest('bad_top'),
    const BadValue(.top, .mapping, WrittenNothing()),
  ),
  CodebaseNamedTwice(
    .parse('app')!,
    first: _manifest('first'),
    second: _manifest('second'),
  ),
  const NoWorkingDirectory('No such file or directory'),
  for (final Os os in Os.values) NoCache(os),
];

ManifestPath _manifest(String stem) => .parse('/consumer/$stem.yaml', .posix)!;

/// The generators the command line's property tests draw from.
extension OutcomeAnys on Any {
  /// A codebase beside the outcome a load gave it.
  Generator<(GitCodebase, FetchOutcome)> get outcome => combine4(
    gitCodebase(),
    choose(OutcomeCase.values),
    intInRange(1, 256),
    choose(['', 'fatal: no such repo\n', 'a\nb']),
    (GitCodebase codebase, OutcomeCase kind, int exitCode, String output) =>
        (codebase, outcomeOf(kind, codebase, exitCode, output)),
  );
}

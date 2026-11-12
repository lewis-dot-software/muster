import 'package:muster/muster.dart';

import 'manifest_refusal_case.dart';

/// A case of [LoadRefusal], each named once in [of], so a case the type
/// gains fails the build until it is named here.
enum RefusalCase {
  /// [NoManifest].
  noManifest,

  /// [NotManifestName].
  notManifestName,

  /// [ManifestMissing].
  manifestMissing,

  /// [ManifestUnreadable].
  manifestUnreadable,

  /// [ManifestInvalid].
  manifestInvalid,

  /// [CodebaseNamedTwice].
  codebaseNamedTwice,

  /// [HostedNotLoaded].
  hostedNotLoaded,

  /// [NoWorkingDirectory].
  noWorkingDirectory,

  /// [NoCache].
  noCache,

  /// [NoClaim].
  noClaim;

  /// The case of [refusal].
  static RefusalCase of(LoadRefusal refusal) => switch (refusal) {
    NoManifest() => .noManifest,
    NotManifestName() => .notManifestName,
    ManifestMissing() => .manifestMissing,
    ManifestUnreadable() => .manifestUnreadable,
    ManifestInvalid() => .manifestInvalid,
    CodebaseNamedTwice() => .codebaseNamedTwice,
    HostedNotLoaded() => .hostedNotLoaded,
    NoWorkingDirectory() => .noWorkingDirectory,
    NoCache() => .noCache,
    NoClaim() => .noClaim,
  };

  /// A refusal of each case, of each [ManifestRefusalCase]'s samples a
  /// manifest's carries, and of no cache on each [Os].
  static final List<LoadRefusal> every = [
    for (final RefusalCase refusal in values) ...refusal.samples,
  ];

  /// Refusals of this case.
  List<LoadRefusal> get samples => switch (this) {
    .noManifest => const [NoManifest()],
    .notManifestName => const [NotManifestName('/consumer/muster.yml')],
    .manifestMissing => [ManifestMissing(_manifest('missing'))],
    .manifestUnreadable => [
      ManifestUnreadable(_manifest('unreadable'), 'Permission denied'),
    ],
    .manifestInvalid => [
      for (final ManifestRefusalCase refusal in ManifestRefusalCase.values)
        for (final ManifestRefusal sample in refusal.samples)
          ManifestInvalid(_manifest(refusal.name), sample),
    ],
    .codebaseNamedTwice => [
      CodebaseNamedTwice(
        .parse('app')!,
        first: _manifest('first'),
        second: _manifest('second'),
      ),
    ],
    .hostedNotLoaded => [HostedNotLoaded(_manifest('hosted'), .parse('args')!)],
    .noWorkingDirectory => const [
      NoWorkingDirectory('No such file or directory'),
    ],
    .noCache => [for (final Os os in Os.values) NoCache(os)],
    .noClaim => const [NoClaim('freebsd')],
  };
}

ManifestPath _manifest(String stem) => .parse('/consumer/$stem.yaml', .posix)!;

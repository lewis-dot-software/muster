import 'package:muster/src/model/manifest_refusal.dart';
import 'package:muster/src/model/written.dart';

import 'manifests.dart';
import 'written_case.dart';

/// A case of [ManifestRefusal], each named once in [of], so a case the type
/// gains fails the build until it is named here.
enum ManifestRefusalCase {
  /// [NotYaml].
  notYaml,

  /// [UnknownKey].
  unknownKey,

  /// [MissingKey].
  missingKey,

  /// [MissingKind].
  missingKind,

  /// [BadValue].
  badValue;

  /// The case of [refusal].
  static ManifestRefusalCase of(ManifestRefusal refusal) => switch (refusal) {
    NotYaml() => .notYaml,
    UnknownKey() => .unknownKey,
    MissingKey() => .missingKey,
    MissingKind() => .missingKind,
    BadValue() => .badValue,
  };

  /// Refusals of this case: one, and a [BadValue] of each [WrittenCase] and
  /// one of the manifest's top.
  List<ManifestRefusal> get samples => switch (this) {
    .notYaml => const [NotYaml('line 1, column 2: Expected node content.')],
    .unknownKey => [
      UnknownKey(pathOf(['depth'])),
    ],
    .missingKey => [
      MissingKey(pathOf(['git'])),
    ],
    .missingKind => [
      MissingKind(pathOf(['codebases', 'app'])),
    ],
    .badValue => [
      for (final WrittenCase written in WrittenCase.values)
        BadValue(
          pathOf(['codebases', 'app', 'toolchain']),
          .toolchain,
          written.sample,
        ),
      const BadValue(.top, .mapping, WrittenNothing()),
    ],
  };
}

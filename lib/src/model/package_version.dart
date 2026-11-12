import 'package:pub_semver/pub_semver.dart';

/// A hosted package's version, in its canonical spelling, so two spellings of
/// one version, `01.2.3` and `1.2.3` among them, are one version.
extension type const PackageVersion._(String version) {
  /// The version [text] is, or null where pub reads no version from it: a
  /// `major.minor.patch`, with a pre-release after `-` and a build after `+`
  /// where it has them.
  static PackageVersion? parse(String text) {
    try {
      return ._(Version.parse(text).canonicalizedVersion);
    } on FormatException {
      return null;
    }
  }
}

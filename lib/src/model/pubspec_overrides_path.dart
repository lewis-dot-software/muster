/// The `pubspec_overrides.yaml` of a package inside a checkout.
extension type const PubspecOverridesPath._(String path) {
  /// The overrides at [path], the `pubspec_overrides.yaml` a package's
  /// directory holds.
  static PubspecOverridesPath inPackage(String path) => ._(path);
}

/// The `pubspec.yaml` of a package inside a checkout.
extension type const PubspecPath._(String path) {
  /// The pubspec at [path], the `pubspec.yaml` a package's directory holds.
  static PubspecPath inPackage(String path) => ._(path);
}

/// The `package_config.json` a package's resolve writes, which a tool reads
/// the package's dependencies from.
extension type const PackageConfigPath._(String path) {
  /// The package config at [path], under a package's `.dart_tool/`.
  static PackageConfigPath inPackage(String path) => ._(path);
}

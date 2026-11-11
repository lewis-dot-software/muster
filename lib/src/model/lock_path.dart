/// The `pubspec.lock` of a package inside a checkout, the lock it resolves
/// on.
extension type const LockPath._(String path) {
  /// The lock at [path], the `pubspec.lock` a package's directory holds.
  static LockPath inPackage(String path) => ._(path);
}

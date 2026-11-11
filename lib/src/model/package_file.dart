/// A file of a package's that muster reads.
enum PackageFile {
  /// Its `pubspec.yaml`.
  pubspec('pubspec.yaml'),

  /// Its `pubspec.lock`.
  lock('pubspec.lock');

  const PackageFile(this.name);

  /// The file's name in its package's directory.
  final String name;
}

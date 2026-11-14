/// What a manifest's value must be for its key to take it.
enum Wanted {
  /// A mapping of keys to values.
  mapping,

  /// A codebase's name, `[a-z][a-z0-9_]*`.
  codebaseName,

  /// A pub package's name, as `dart pub get` takes one.
  packageName,

  /// A git URL, neither empty nor opening on `-`.
  gitUrl,

  /// A commit's full hash, 40 or 64 lowercase hexadecimal digits.
  fullHash,

  /// A toolchain's name, `dart` or `flutter`.
  toolchain,

  /// A relative path that stays inside its repo.
  rootInsideRepo,

  /// A version pub reads, as `1.2.3` or `2.0.0-dev.1` is.
  version,

  /// A hosted package's resolution, `alone` or `as-dependency`.
  resolution,
}

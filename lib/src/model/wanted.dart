/// What a manifest's value must be for its key to take it.
enum Wanted {
  /// A mapping of keys to values.
  mapping,

  /// A codebase's name, a pub package name: `[a-z][a-z0-9_]*`.
  packageName,

  /// A git URL, neither empty nor opening on `-`.
  gitUrl,

  /// A commit's full hash, 40 or 64 lowercase hexadecimal digits.
  fullHash,

  /// A toolchain's name, `dart` or `flutter`.
  toolchain,

  /// A relative path that stays inside its repo.
  rootInsideRepo,
}

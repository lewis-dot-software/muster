/// Where the lock a package resolves on comes from.
enum LockSource {
  /// The `pubspec.lock` its commit holds.
  committed,

  /// The kept lock beside its manifest.
  kept,
}

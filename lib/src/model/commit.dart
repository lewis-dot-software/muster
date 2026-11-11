/// A git commit, named by its full hash.
extension type const Commit._(String hash) {
  /// The commit [text] names, or null where it is not a full hash: 40
  /// lowercase hexadecimal digits for SHA-1, or 64 for SHA-256, so no branch,
  /// tag or abbreviation passes for a pin.
  static Commit? parse(String text) =>
      _fullHash.hasMatch(text) ? ._(text) : null;
}

final RegExp _fullHash = .new(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');

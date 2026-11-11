/// Where a key sits in a manifest, each key from the top joined by `.`, as
/// `codebases.app.root` is.
extension type const KeyPath._(String dotted) {
  /// The top of a manifest, above every key.
  static const KeyPath top = ._('');

  /// The path of [key] inside the mapping at this path.
  KeyPath child(Object? key) => ._(dotted.isEmpty ? '$key' : '$dotted.$key');
}

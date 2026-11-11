/// A codebase's name, a pub package name, since it names a directory, a stamp
/// and a kept lock.
extension type const CodebaseName._(String name) {
  /// The name [text] is, or null where it is no pub package name:
  /// `[a-z][a-z0-9_]*`.
  static CodebaseName? parse(String text) =>
      _packageName.hasMatch(text) ? ._(text) : null;
}

final RegExp _packageName = .new(r'^[a-z][a-z0-9_]*$');

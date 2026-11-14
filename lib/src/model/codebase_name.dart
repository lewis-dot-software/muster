/// A codebase's name, `[a-z][a-z0-9_]*`, since it names a directory, a stamp
/// and a kept lock.
extension type const CodebaseName._(String name) {
  /// The name [text] is, or null where it is no codebase name.
  static CodebaseName? parse(String text) =>
      _codebaseName.hasMatch(text) ? ._(text) : null;
}

final RegExp _codebaseName = .new(r'^[a-z][a-z0-9_]*$');

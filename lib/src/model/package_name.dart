/// A pub package's name, as a hosted codebase names the package it fetches.
extension type const PackageName._(String name) {
  /// The name [text] is, or null where it is no pub package name:
  /// `[a-z][a-z0-9_]*`.
  static PackageName? parse(String text) =>
      _packageName.hasMatch(text) ? ._(text) : null;
}

final RegExp _packageName = .new(r'^[a-z][a-z0-9_]*$');

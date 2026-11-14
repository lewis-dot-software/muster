/// A pub package's name, as a hosted codebase names the package it fetches.
extension type const PackageName._(String name) {
  /// The name [text] is, or null where `dart pub get` refuses it as a
  /// package's name: one that is neither a Dart identifier nor identifiers
  /// joined by `.`, `[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*`, or
  /// one that is a word pub reserves, in any case.
  static PackageName? parse(String text) =>
      _packageName.hasMatch(text) && !_reserved.contains(text.toLowerCase())
      ? ._(text)
      : null;
}

final RegExp _packageName = .new(
  r'^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$',
);

/// The words pub refuses as a package's name: Dart's reserved words, but for
/// the ones pub lets stand since a package on pub.dev already bears each,
/// `async`, `base`, `dynamic`, `extension`, `factory`, `get`, `show`,
/// `static`, `sync`, `typedef` and `when`.
const Set<String> _reserved = {
  'abstract',
  'as',
  'assert',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'else',
  'enum',
  'export',
  'extends',
  'external',
  'false',
  'final',
  'finally',
  'for',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'inline',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

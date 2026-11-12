import 'package_name.dart';

/// A codebase's name, a pub package name, since it names a directory, a stamp
/// and a kept lock.
extension type const CodebaseName._(String name) {
  /// The name [text] is, or null where it is no pub package name, as
  /// [PackageName.parse] reads one.
  static CodebaseName? parse(String text) =>
      PackageName.parse(text) == null ? null : ._(text);
}

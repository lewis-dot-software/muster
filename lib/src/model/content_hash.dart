import 'package:crypto/crypto.dart';

/// A file's contents, named by a SHA-256 of them, in lowercase hexadecimal.
extension type const ContentHash._(String hex) {
  /// The hash of [bytes].
  static ContentHash of(List<int> bytes) =>
      ._(sha256.convert(bytes).toString());

  /// The hash [text] is, or null where it is not 64 lowercase hexadecimal
  /// digits.
  static ContentHash? parse(String text) =>
      _sha256.hasMatch(text) ? ._(text) : null;
}

final RegExp _sha256 = .new(r'^[0-9a-f]{64}$');

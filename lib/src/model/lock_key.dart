import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'git_codebase.dart';

/// The key a kept lock's file is named by: a SHA-256, in hexadecimal, of every
/// manifest value a codebase's resolve turns on, so an edit to any of them
/// finds no lock made for other values.
extension type const LockKey._(String hex) {
  /// The key of [codebase]'s kept lock, from its URL as written, its commit,
  /// its root and its toolchain, and nothing else of its manifest.
  static LockKey of(GitCodebase codebase) => ._(
    sha256
        .convert(
          utf8.encode(
            // A JSON list of strings reads back to its strings alone, so no
            // two codebases' values run together into one key.
            jsonEncode([
              'git',
              codebase.url,
              codebase.commit,
              codebase.root,
              codebase.toolchain.name,
            ]),
          ),
        )
        .toString(),
  );
}

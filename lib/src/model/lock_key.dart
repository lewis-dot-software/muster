import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'codebase.dart';
import 'git_codebase.dart';
import 'hosted_codebase.dart';

/// The key a kept lock's file is named by: a SHA-256, in hexadecimal, of every
/// manifest value a codebase's resolve turns on, so an edit to any of them
/// finds no lock made for other values.
extension type const LockKey._(String hex) {
  /// The key of [codebase]'s kept lock, from its kind and nothing else of its
  /// manifest but a git codebase's URL as written, its commit, its root and
  /// its toolchain, or a hosted one's package, its version, its resolution
  /// and its toolchain.
  static LockKey of(Codebase codebase) => ._(
    sha256
        .convert(
          utf8.encode(
            // A JSON list of strings reads back to its strings alone, so no
            // two codebases' values run together into one key, and its first
            // names the kind, so no git codebase's key is a hosted one's.
            jsonEncode(switch (codebase) {
              Git(codebase: final GitCodebase git) => [
                'git',
                git.url,
                git.commit,
                git.root,
                git.toolchain.name,
              ],
              Hosted(codebase: final HostedCodebase hosted) => [
                'hosted',
                hosted.package,
                hosted.version,
                hosted.resolution.word,
                hosted.toolchain.name,
              ],
            }),
          ),
        )
        .toString(),
  );
}

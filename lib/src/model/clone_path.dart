import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cache_directory.dart';
import 'claim_path.dart';
import 'git_url.dart';

/// The directory of one git URL's bare clone in the cache.
extension type const ClonePath._(String path) {
  /// The clone of [url] in [cache], named by a SHA-256, in hexadecimal, of the
  /// URL as written, so two spellings of one repo are two clones, and joined
  /// in the cache's own path style.
  static ClonePath of(CacheDirectory cache, GitUrl url) =>
      ._(cache.os.paths.join(cache.path, _name(url)));

  /// The clone in [cache] whose temporary clone is the entry [name] of the
  /// cache's directory, or null where [name] is no temporary clone's. A
  /// name of `<hash>.partial` with no token is a temporary clone's too, so
  /// one that a build of muster naming none left in the shared cache is
  /// read as the rest are.
  static ClonePath? ofTemporary(CacheDirectory cache, String name) =>
      switch (_temporary.firstMatch(name)) {
        final RegExpMatch match => ._(
          cache.os.paths.join(cache.path, match[1]),
        ),
        null => null,
      };

  /// The name each temporary clone of [url]'s clone opens with, a token
  /// after it: the clone's own name, then `.partial.`.
  static String temporaryPrefix(GitUrl url) => '${_name(url)}$_suffix.';

  /// The claim on the clone, the file beside it named `<hash>.claim`.
  ClaimPath get claim => .ofClone(this);
}

/// A clone's name: a SHA-256, in hexadecimal, of [url] as written.
String _name(GitUrl url) => sha256.convert(utf8.encode(url.url)).toString();

/// What a temporary clone's name holds after its clone's, before any token.
const String _suffix = '.partial';

/// A temporary clone's name: its clone's SHA-256, its suffix, then a dot and
/// its token where it has one.
final RegExp _temporary = .new(
  '^([0-9a-f]{64})${RegExp.escape(_suffix)}(?:\\..+)?\$',
);

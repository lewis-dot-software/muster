import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cache_directory.dart';
import 'claim_path.dart';
import 'git_url.dart';
import 'temporary_clone_path.dart';

/// The directory of one git URL's bare clone in the cache.
extension type const ClonePath._(String path) {
  /// The clone of [url] in [cache], named by a SHA-256, in hexadecimal, of the
  /// URL as written, so two spellings of one repo are two clones, and joined
  /// in the cache's own path style.
  static ClonePath of(CacheDirectory cache, GitUrl url) => ._(
    cache.os.paths.join(
      cache.path,
      sha256.convert(utf8.encode(url.url)).toString(),
    ),
  );

  /// The clone in [cache] whose temporary clone is the entry [name] of the
  /// cache's directory, or null where [name] is no temporary clone's.
  static ClonePath? ofTemporary(CacheDirectory cache, String name) =>
      switch (_temporary.firstMatch(name)) {
        final RegExpMatch match => ._(
          cache.os.paths.join(cache.path, match[1]),
        ),
        null => null,
      };

  /// The claim on the clone, the file beside it named `<hash>.claim`.
  ClaimPath get claim => .ofClone(this);

  /// The directory the clone is made in before it moves into place, beside
  /// it named `<hash>.partial`.
  TemporaryClonePath get temporary => .of(this);
}

/// A temporary clone's name: its clone's SHA-256, then its suffix.
final RegExp _temporary = .new(
  '^([0-9a-f]{64})${RegExp.escape(temporaryCloneSuffix)}\$',
);

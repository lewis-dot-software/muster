import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cache_directory.dart';
import 'git_url.dart';

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
}

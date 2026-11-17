import 'dart:io';

import 'package:muster/src/model/cache_directory.dart';
import 'package:muster/src/model/clone_path.dart';
import 'package:path/path.dart' as p;

/// The path of each temporary clone of [clone] standing in [cache], none
/// where the cache's directory is not there.
Future<List<String>> temporaryClonesOf(
  CacheDirectory cache,
  ClonePath clone,
) async {
  final Directory directory = .new(cache.path);
  if (!await directory.exists()) {
    return const [];
  }
  return [
    await for (final FileSystemEntity entity in directory.list())
      if (ClonePath.ofTemporary(cache, p.basename(entity.path)) == clone)
        entity.path,
  ];
}

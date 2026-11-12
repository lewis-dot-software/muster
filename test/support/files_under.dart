import 'dart:io';

import 'package:path/path.dart' as p;

/// Every file under [directory], from its top in `/` separators, beside its
/// contents, less each path of [less] and everything under it.
Future<Map<String, String>> filesUnder(
  String directory, {
  List<String> less = const ['.git'],
}) async => {
  await for (final FileSystemEntity entity in Directory(
    directory,
  ).list(recursive: true, followLinks: false))
    if (entity is File)
      if (p.posix.joinAll(p.split(p.relative(entity.path, from: directory)))
          case final String path
          when !less.any(
            (String left) => path == left || path.startsWith('$left/'),
          ))
        path: await entity.readAsString(),
};

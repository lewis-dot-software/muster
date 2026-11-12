import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Every file, directory and link under [directory], beside a file's bytes
/// in base64, and a directory's or a link's mark.
Future<Map<String, String>> treeUnder(String directory) async => {
  await for (final FileSystemEntity entity in Directory(
    directory,
  ).list(recursive: true, followLinks: false))
    p.relative(entity.path, from: directory): switch (entity) {
      File() => base64Encode(await entity.readAsBytes()),
      Directory() => '<directory>',
      Link() => '<link ${await entity.target()}>',
      _ => throw StateError('neither a file, a directory nor a link: $entity'),
    },
};

import 'dart:io';

/// Writes [text] as the file at [path], its directory made.
Future<void> writeFile(String path, String text) async {
  await File(path).create(recursive: true);
  await File(path).writeAsString(text);
}

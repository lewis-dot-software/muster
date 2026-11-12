import 'dart:io';

import 'package:test/test.dart';

/// Sets [entity]'s permissions to [mode], as `chmod` reads it, and fails the
/// test where `chmod` fails.
Future<void> chmod(String mode, FileSystemEntity entity) async {
  final ProcessResult result = await Process.run('chmod', [mode, entity.path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

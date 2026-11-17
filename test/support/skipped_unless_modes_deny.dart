import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'chmod.dart';

/// Whether the running test is marked skipped, as it is where this process
/// writes into a directory whose mode denies a write, as root does, probed
/// in a directory made under [parent] and removed after.
Future<bool> skippedUnlessModesDeny(Directory parent) async {
  final Directory probe = await parent.createTemp('modes-');
  await chmod('555', probe);
  try {
    await File(p.join(probe.path, 'written')).create();
  } on FileSystemException {
    return false;
  } finally {
    await chmod('755', probe);
    await probe.delete(recursive: true);
  }
  markTestSkipped('a mode denies this user nothing, as it denies root nothing');
  return true;
}

import 'dart:io';

import '../model/fetch_outcome.dart';
import 'file_act.dart';
import 'store_fault.dart';

/// Removes the directory at [path] with everything in it, where it is there.
/// A file or a link there is removed in its place, and a link's target is
/// left.
///
/// Throws a [StoreFault] of [StoreFailed] where it cannot be removed.
Future<void> removeDirectory(String path) => fileAct(path, () async {
  try {
    await Directory(path).delete(recursive: true);
  } on PathNotFoundException {
    return;
  }
});

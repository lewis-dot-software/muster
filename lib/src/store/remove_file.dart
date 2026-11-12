import 'dart:io';

import '../model/fetch_outcome.dart';
import 'file_act.dart';
import 'store_fault.dart';

/// Removes the file at [path], where it is there.
///
/// Throws a [StoreFault] of [StoreFailed] where it cannot be removed.
Future<void> removeFile(String path) => fileAct(path, () async {
  try {
    await File(path).delete();
  } on PathNotFoundException {
    return;
  }
});

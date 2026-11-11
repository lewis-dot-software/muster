import 'dart:io';

import '../model/fetch_failure.dart';
import 'file_act.dart';
import 'store_fault.dart';

/// The bytes of the file at [path], or null where nothing is there.
///
/// Throws a [StoreFault] of [StoreFailed] where a file there cannot be read.
Future<List<int>?> bytesIfThere(String path) => fileAct(path, () async {
  try {
    return await File(path).readAsBytes();
  } on PathNotFoundException {
    return null;
  }
});

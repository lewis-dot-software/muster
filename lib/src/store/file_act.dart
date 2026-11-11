import 'dart:io';

import '../model/fetch_outcome.dart';
import 'store_fault.dart';

/// [act] on [path], its failure thrown as a [StoreFault] of [StoreFailed].
Future<T> fileAct<T>(String path, Future<T> Function() act) async {
  try {
    return await act();
  } on FileSystemException catch (e) {
    throw StoreFault(
      StoreFailed(e.path ?? path, e.osError?.message ?? e.message),
    );
  }
}

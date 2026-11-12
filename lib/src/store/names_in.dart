import 'dart:io';

import '../model/fetch_outcome.dart';
import '../model/locks_directory.dart';
import 'file_act.dart';
import 'store_fault.dart';

/// The name of every file in [locks], none where the directory is not
/// there.
///
/// Throws a [StoreFault] of [StoreFailed] where the directory cannot be
/// read.
Future<List<String>> namesIn(LocksDirectory locks) =>
    fileAct(locks.path, () async {
      final Directory directory = .new(locks.path);
      if (!await directory.exists()) {
        return const [];
      }
      return [
        await for (final FileSystemEntity entity in directory.list())
          if (entity is File) locks.os.paths.basename(entity.path),
      ];
    });

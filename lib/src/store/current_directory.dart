import 'dart:io';

import '../model/fetch_outcome.dart';
import '../model/os.dart';
import '../model/working_directory.dart';
import 'file_act.dart';
import 'store_fault.dart';

/// The working directory of the process muster runs in, written in [os]'s
/// paths.
///
/// Throws a [StoreFault] of [StoreFailed] where the system cannot give it, as
/// where the directory has been deleted.
Future<WorkingDirectory> currentDirectory(Os os) =>
    fileAct('.', () async => .new(Directory.current.path, os));

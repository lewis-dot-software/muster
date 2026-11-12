import 'dart:io';

import '../model/os.dart';
import '../model/temp_directory.dart';

/// The temporary directory of the system muster runs on, written in [os]'s
/// paths.
TempDirectory systemTemp(Os os) => .new(Directory.systemTemp.path, os);

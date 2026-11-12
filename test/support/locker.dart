import 'dart:io';

import 'package:muster/src/store/locker.dart';

/// The locker of the POSIX system the tests run on, its C library bound once
/// for the test's isolate.
final Locker testLocker = .of(.posix, Platform.operatingSystem)!;

import 'dart:io';

import '../model/environment.dart';

/// The environment of the process muster runs in, read from it whole.
Environment processEnvironment() => (
  variables: Platform.environment,
  os: Platform.isWindows ? .windows : .posix,
);

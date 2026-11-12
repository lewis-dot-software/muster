import 'dart:io';

import 'git.dart';

/// The variables a caller's environment could hold that would have git or
/// ssh ask on the terminal or through a program of its own.
const List<String> _askers = [
  'GIT_ASKPASS',
  'GIT_TERMINAL_PROMPT',
  'SSH_ASKPASS',
  'SSH_ASKPASS_REQUIRE',
];

/// The test process's environment, made hermetic in [temp], with none of
/// the variables that would have git or ssh ask.
Map<String, String> quietIn(Directory temp) =>
    hermetic(temp)..removeWhere((String key, _) => _askers.contains(key));

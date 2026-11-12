import 'package:muster/src/model/command.dart';

/// The command a contender's load holds until its test's word.
enum Pause {
  /// The first command on the clone: its clone, or any git command named on
  /// it by `--git-dir`.
  clone,

  /// The checkout's own make: the worktree's add, or its checkout at the
  /// pin.
  place,

  /// A package's resolve.
  resolve;

  /// Whether [command] is the one this pause names.
  bool holds(Command command) => switch (this) {
    .clone => switch (command.executable) {
      .git =>
        command.arguments.first == 'clone' ||
            command.arguments.first.startsWith('--git-dir='),
      .dart || .flutter => false,
    },
    .place => switch (command.executable) {
      .git =>
        (command.arguments.contains('worktree') &&
                command.arguments.contains('add')) ||
            command.arguments.contains('checkout'),
      .dart || .flutter => false,
    },
    .resolve => switch (command.executable) {
      .git => false,
      .dart || .flutter => command.arguments.contains('get'),
    },
  };
}

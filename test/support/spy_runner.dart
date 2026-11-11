import 'package:muster/src/model/command.dart';
import 'package:muster/src/store/ran.dart';
import 'package:muster/src/store/runner.dart';

/// A runner that keeps every command it is given, in order, then runs it,
/// or answers it in place of running it where [answer] gives what it left.
class SpyRunner extends Runner {
  /// The spy that starts each process with [environment].
  SpyRunner(super.environment);

  /// Every command given so far.
  final List<Command> commands = [];

  /// Each command given so far, by its executable and its arguments.
  List<String> get given => [
    for (final Command command in commands)
      '${command.executable.name} ${command.arguments.join(' ')}',
  ];

  /// What a command left in place of its run, or null where it runs.
  Ran? Function(Command command) answer = (Command command) => null;

  /// Whether any command given so far reached a URL, by a fetch or a clone.
  bool get fetched => commands.any(
    (Command command) =>
        command.arguments.contains('fetch') ||
        command.arguments.contains('clone'),
  );

  @override
  Future<Ran> run(Command command, {Set<int> exits = const {0}}) {
    commands.add(command);
    return switch (answer(command)) {
      final Ran ran => .value(ran),
      null => super.run(command, exits: exits),
    };
  }
}

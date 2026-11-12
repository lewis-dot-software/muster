import 'package:muster/src/model/command.dart';
import 'package:muster/src/store/ran.dart';
import 'package:muster/src/store/runner.dart';

/// A runner that keeps every command it is given, in order, awaits [before]
/// on it, then runs it, or answers it in place of running it where [answer]
/// gives what it left, then awaits [after] on it.
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

  /// What runs on each command once it is kept, before it runs or is
  /// answered, which may hold it or throw in place of its run.
  Future<void> Function(Command command) before = (Command command) async {};

  /// What runs on each command once it has run, or been answered, with an
  /// exit it allows, which may hold it or throw in place of its result.
  Future<void> Function(Command command) after = (Command command) async {};

  /// Whether any command given so far reached a URL, by a fetch or a clone.
  bool get fetched => commands.any(
    (Command command) =>
        command.arguments.contains('fetch') ||
        command.arguments.contains('clone'),
  );

  @override
  Future<Ran> run(Command command, {Set<int> exits = const {0}}) async {
    commands.add(command);
    await before(command);
    final Ran ran = switch (answer(command)) {
      final Ran ran => ran,
      null => await super.run(command, exits: exits),
    };
    await after(command);
    return ran;
  }
}

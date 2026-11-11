import 'package:muster/src/model/command.dart';
import 'package:muster/src/store/ran.dart';
import 'package:muster/src/store/runner.dart';

/// A runner that keeps every command it is given, in order, then runs it.
class SpyRunner extends Runner {
  /// The spy that starts each process with [environment].
  SpyRunner(super.environment);

  /// Every command given so far.
  final List<Command> commands = [];

  /// Whether any command given so far reached a URL, by a fetch or a clone.
  bool get fetched => commands.any(
    (Command command) =>
        command.arguments.contains('fetch') ||
        command.arguments.contains('clone'),
  );

  @override
  Future<Ran> run(Command command, {Set<int> exits = const {0}}) {
    commands.add(command);
    return super.run(command, exits: exits);
  }
}

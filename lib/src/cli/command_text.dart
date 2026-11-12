import '../model/command.dart';

/// [command] as a shell line would start it, each argument after its
/// executable.
String commandText(Command command) =>
    [command.executable.name, ...command.arguments].join(' ');

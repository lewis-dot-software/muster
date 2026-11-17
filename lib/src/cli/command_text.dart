import '../model/command.dart';

/// [command] as its executable and each argument after it, joined by
/// spaces, unquoted.
String commandText(Command command) =>
    [command.executable.name, ...command.arguments].join(' ');

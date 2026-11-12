import '../model/command.dart';
import '../model/fetch_outcome.dart';
import 'command_text.dart';

/// What a failure's row leaves out, for a person to act on, or null where
/// the row says it all: a command's exit code and output, and what the
/// system said of a file act.
String? failureNote(FetchFailure failure) => switch (failure) {
  CommandFailed(
    :final Command command,
    :final int exitCode,
    :final String stdout,
    :final String stderr,
  ) =>
    '${commandText(command)} exited $exitCode'
        '${_block(stdout)}${_block(stderr)}',
  StoreFailed(:final String path, :final String reason) => '$path: $reason',
  Unlocked() || Unstartable() || PinMissing() => null,
};

String _block(String output) =>
    output.trim().isEmpty ? '' : '\n${output.trimRight()}';

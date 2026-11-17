import '../model/command.dart';
import '../model/fetch_outcome.dart';
import 'command_text.dart';
import 'outcome_cells.dart';

/// A failure's outcome and its own detail, as a row's cells give them: the
/// lock for [Unlocked], the command for [CommandFailed], the executable for
/// [Unstartable], the path for [StoreFailed] and the commit for
/// [PinMissing].
OutcomeCells failureCells(FetchFailure failure) => switch (failure) {
  Unlocked(:final lock) => ('Unlocked', lock.path),
  CommandFailed(:final Command command) => (
    'CommandFailed',
    commandText(command),
  ),
  Unstartable(:final executable) => ('Unstartable', executable.name),
  StoreFailed(:final String path) => ('StoreFailed', path),
  PinMissing(:final commit) => ('PinMissing', commit.hash),
};

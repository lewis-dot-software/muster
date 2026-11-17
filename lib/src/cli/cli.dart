import 'package:args/args.dart';

import '../load/load.dart';
import '../load/loads.dart';
import '../load/locking.dart';
import '../model/codebase_name.dart';
import '../model/fetch_outcome.dart';
import '../model/kept_lock_path.dart';
import '../model/lock_outcome.dart';
import '../model/lock_removal.dart';
import 'exit_code.dart';
import 'as_fetch_failure.dart';
import 'cell.dart';
import 'failure_cells.dart';
import 'failure_note.dart';
import 'fetched_detail.dart';
import 'refusal_text.dart';
import 'verb.dart';

/// The `muster` command line: `fetch` and `lock` over the manifests named,
/// each run through [Loads], its rows and its `--help` usage written to one
/// sink, and everything else for a person to another.
final class Cli {
  /// The command line whose runs go through [_loads], its rows written to
  /// [_out] and its refusals, its failures' notes and its usage errors to
  /// [_err].
  Cli(this._loads, this._out, this._err);

  final Loads _loads;

  final StringSink _out;

  final StringSink _err;

  /// Runs the command [arguments] name, and gives the code to exit with.
  ///
  /// `fetch [manifest...]` loads and writes a row per codebase, tab-separated
  /// under a header: its name, its outcome and that outcome's own detail.
  /// `lock [manifest...]` writes the kept locks the codebases lack and removes
  /// those no codebase names, writing under the same header a row per lock
  /// written, per codebase that failed and per removal, a removal's name cell
  /// empty, since no codebase names what it removes. With no manifest named,
  /// each reads `muster.yaml` in the working directory and every manifest
  /// `MUSTER_MANIFESTS` lists. A refused run writes why and no rows.
  Future<ExitCode> run(List<String> arguments) async {
    final ArgResults parsed;
    try {
      parsed = _parser.parse(arguments);
    } on FormatException catch (e) {
      _err
        ..writeln(e.message)
        ..writeln()
        ..write(_usage);
      return .usage;
    }
    final ArgResults? command = parsed.command;
    if (parsed.flag(_help) || (command?.flag(_help) ?? false)) {
      _out.write(_usage);
      return .done;
    }
    if (command == null) {
      if (parsed.rest case [final String word, ...]) {
        _err
          ..writeln('no command named $word')
          ..writeln();
      }
      _err.write(_usage);
      return .usage;
    }
    final List<String> manifests = command.rest;
    return switch (Verb.values.byName(command.name!)) {
      .fetch => _fetch(await _loads.load(named: manifests)),
      .lock => _lock(await _loads.lock(named: manifests)),
    };
  }

  ExitCode _fetch(Load load) {
    switch (load) {
      case Refused(:final reason):
        _err.writeln(refusalText(reason));
        return .refused;
      case Loaded(:final Map<CodebaseName, FetchOutcome> outcomes):
        _row('name', 'outcome', 'detail');
        final List<_Failed> failures = [];
        for (final MapEntry(key: CodebaseName name, value: FetchOutcome outcome)
            in outcomes.entries) {
          switch (outcome) {
            case final Fetched fetched:
              _row(name.name, 'Fetched', fetchedDetail(fetched));
            case final FetchFailure failure:
              final (String shown, String detail) = failureCells(failure);
              _row(name.name, shown, detail);
              failures.add((name, failure));
          }
        }
        _notes(failures);
        return failures.isEmpty ? .done : .failed;
    }
  }

  ExitCode _lock(Locking locking) {
    switch (locking) {
      case LockRefused(:final reason):
        _err.writeln(refusalText(reason));
        return .refused;
      case Locked(
        :final Map<CodebaseName, LockOutcome> outcomes,
        :final removals,
      ):
        _row('name', 'outcome', 'detail');
        final List<_Failed> failures = [];
        for (final MapEntry(key: CodebaseName name, value: LockOutcome outcome)
            in outcomes.entries) {
          switch (outcome) {
            case LocksWritten(:final List<KeptLockPath> locks):
              for (final KeptLockPath lock in locks) {
                _row(name.name, 'Wrote', lock.path);
              }
            case LockFailed(:final ActFailure failure):
              final FetchFailure failed = asFetchFailure(failure);
              final (String shown, String detail) = failureCells(failed);
              _row(name.name, shown, detail);
              failures.add((name, failed));
          }
        }
        final List<StoreFailed> unremoved = [];
        for (final LockRemoval removal in removals) {
          switch (removal) {
            case LockRemoved(:final KeptLockPath lock):
              _row('', 'Removed', lock.path);
            case RemovalFailed(:final StoreFailed failure):
              final (String shown, String detail) = failureCells(failure);
              _row('', shown, detail);
              unremoved.add(failure);
          }
        }
        _notes(failures);
        for (final StoreFailed failure in unremoved) {
          _err.writeln(failureNote(failure));
        }
        return failures.isEmpty && unremoved.isEmpty ? .done : .failed;
    }
  }

  /// Writes a row of [name], [outcome] and [detail], its detail a [cell].
  void _row(String name, String outcome, String detail) =>
      _out.writeln('$name\t$outcome\t${cell(detail)}');

  /// Writes each of [failures]' notes, headed by its codebase's name, in
  /// their rows' order.
  void _notes(List<_Failed> failures) {
    for (final (CodebaseName name, FetchFailure failure) in failures) {
      if (failureNote(failure) case final String note) {
        _err.writeln('${name.name}: $note');
      }
    }
  }
}

/// A codebase's failure, as a run's notes give it: the `name` of the
/// codebase, and the `failure` its row shows.
typedef _Failed = (CodebaseName name, FetchFailure failure);

const String _help = 'help';

final ArgParser _parser = () {
  final ArgParser parser = .new()
    ..addFlag(_help, abbr: 'h', negatable: false, help: 'Prints this usage.');
  for (final Verb verb in Verb.values) {
    parser
        .addCommand(verb.name)
        .addFlag(_help, abbr: 'h', negatable: false, help: 'Prints the usage.');
  }
  return parser;
}();

final String _usage = [
  'Usage: muster <command> [manifest...]',
  '',
  'Brings the codebases the manifests name to their pins, resolved. With no',
  'manifest named, a command reads muster.yaml in the working directory and',
  'every manifest MUSTER_MANIFESTS lists.',
  '',
  'Commands:',
  for (final Verb verb in Verb.values)
    '  ${verb.name.padRight(7)}${verb.summary}',
  '',
].join('\n');

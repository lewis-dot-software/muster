import 'dart:convert';

import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/cli/as_fetch_failure.dart';
import 'package:muster/src/cli/cli.dart';
import 'package:muster/src/cli/exit_code.dart';
import 'package:muster/src/cli/failure_note.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/lock_outcome.dart';
import 'package:muster/src/model/lock_removal.dart';
import 'package:muster/src/model/quoted.dart';
import 'package:test/test.dart';

import '../support/fixed_loads.dart';
import '../support/lines_of.dart';
import '../support/outcomes.dart';
import '../support/refusal_case.dart';

/// The detail an outcome's row carries, read off the outcome by its case.
String _detail(FetchOutcome outcome) => switch (outcome) {
  Fetched(:final package, :final example) => switch (example) {
    NoExample() || ExampleResolved() => package.path,
    ExampleUnresolved(outside: (:final dependency, :final path)) =>
      '${package.path} (example unresolved: ${dependency.name} at '
          '${quoted(path)})',
  },
  Unlocked(:final lock) => lock.path,
  CommandFailed(:final command) => [
    command.executable.name,
    ...command.arguments,
  ].join(' '),
  Unstartable(:final executable) => executable.name,
  StoreFailed(:final String path) => path,
  PinMissing(:final commit) => commit.hash,
};

/// The text [cell] gives: the text quoted in it where it opens on `"`, and
/// [cell] itself otherwise.
String _read(String cell) =>
    cell.startsWith('"') ? jsonDecode(cell) as String : cell;

/// The row of an outcome of [name]'s: its name, its outcome and that
/// outcome's own detail.
List<String> _outcomeRow(String name, FetchOutcome outcome) => [
  name,
  '${outcome.runtimeType}',
  _detail(outcome),
];

/// The rows a lock giving [outcomes] and [removals] prints after its header:
/// one per lock written, per codebase whose lock failed and per removal, a
/// removal's name empty.
List<List<String>> _lockRows(
  Map<CodebaseName, LockOutcome> outcomes,
  List<LockRemoval> removals,
) => [
  for (final MapEntry(key: CodebaseName name, value: LockOutcome outcome)
      in outcomes.entries)
    ...switch (outcome) {
      LocksWritten(:final List<KeptLockPath> locks) => [
        for (final KeptLockPath lock in locks) [name.name, 'Wrote', lock.path],
      ],
      LockFailed(:final ActFailure failure) => [
        _outcomeRow(name.name, asFetchFailure(failure)),
      ],
    },
  for (final LockRemoval removal in removals)
    switch (removal) {
      LockRemoved(:final KeptLockPath lock) => ['', 'Removed', lock.path],
      RemovalFailed(:final StoreFailed failure) => _outcomeRow('', failure),
    },
];

/// Every control character, a tab among them, and Unicode's line breaks.
final RegExp _control = .new(r'[\x00-\x1f\x7f-\x9f\u2028\u2029]');

/// What [loads] writes to its rows' sink for [verb].
Future<String> _rowsOf(FixedLoads loads, String verb) async {
  final StringBuffer out = .new();
  await Cli(loads, out, StringBuffer()).run([verb]);
  return '$out';
}

void main() {
  property("CLI-1: `muster fetch`: prints one row for each codebase in the "
      "load's order, its name, its outcome and that outcome's own detail, "
      "prints each failure's note to standard error in its row's order, "
      "exits 0 when every outcome is `Fetched`, 1 when any is not, and 2 "
      "with the refusal's line alone when the load is refused.", (
    Draw draw,
  ) async {
    final List<DrawnOutcome> drawn = draw(.list(anyOutcome), label: 'drawn');
    final int refusal = draw(
      .integer(
        min: -RefusalCase.every.length,
        max: RefusalCase.every.length - 1,
      ),
      label: 'refusal',
    );
    final Map<CodebaseName, FetchOutcome> outcomes = {
      for (final (GitCodebase codebase, FetchOutcome outcome) in drawn)
        codebase.name: outcome,
    };
    final StringBuffer out = .new();
    final StringBuffer err = .new();
    final ExitCode code = await Cli(
      refusal < 0
          ? FixedLoads.loading(outcomes)
          : FixedLoads(loads: Refused(RefusalCase.every[refusal])),
      out,
      err,
    ).run(['fetch']);
    if (refusal >= 0) {
      expect('$out', isEmpty);
      expect('$err', '${RefusalCase.every[refusal]}\n');
      expect(code, ExitCode.refused);
      return;
    }
    expect(
      [
        for (final List<String> cells in linesOf('$out'))
          switch (cells) {
            [final String name, final String outcome, final String detail] => [
              name,
              outcome,
              _read(detail),
            ],
            _ => cells,
          },
      ],
      [
        ['name', 'outcome', 'detail'],
        for (final MapEntry(key: CodebaseName name, value: FetchOutcome outcome)
            in outcomes.entries)
          _outcomeRow(name.name, outcome),
      ],
    );
    final List<String> notes = [
      for (final MapEntry(key: CodebaseName name, value: FetchOutcome outcome)
          in outcomes.entries)
        if (outcome case final FetchFailure failure)
          if (failureNote(failure) case final String note)
            '${name.name}: $note\n',
    ];
    expect('$err', notes.join());
    expect(
      code,
      outcomes.values.every(
            (FetchOutcome o) => switch (o) {
              Fetched() => true,
              FetchFailure() => false,
            },
          )
          ? ExitCode.done
          : ExitCode.failed,
    );
  });

  property("CLI-2: Every row `muster fetch` and `muster lock` print holds its "
      "header's three cells, each one line with no control character that "
      'reads back as the text it stands for, whatever a URL, a path or a '
      'command carries.', (Draw draw) async {
    final List<DrawnOutcome> fetchedDrawn = draw(
      .list(anyOutcome),
      label: 'fetchedDrawn',
    );
    final List<DrawnLockOutcome> lockedDrawn = draw(
      .list(anyLockOutcome),
      label: 'lockedDrawn',
    );
    final List<LockRemoval> removals = draw(
      .list(anyRemoval),
      label: 'removals',
    );
    final Map<CodebaseName, FetchOutcome> fetched = {
      for (final (GitCodebase codebase, FetchOutcome outcome) in fetchedDrawn)
        codebase.name: outcome,
    };
    final Map<CodebaseName, LockOutcome> locked = {
      for (final (GitCodebase codebase, LockOutcome outcome) in lockedDrawn)
        codebase.name: outcome,
    };
    for (final (String verb, FixedLoads loads, List<List<String>> rows) in [
      (
        'fetch',
        .loading(fetched),
        [
          for (final MapEntry(
                key: CodebaseName name,
                value: FetchOutcome outcome,
              )
              in fetched.entries)
            _outcomeRow(name.name, outcome),
        ],
      ),
      (
        'lock',
        .new(locks: Locked(locked, removals)),
        _lockRows(locked, removals),
      ),
    ]) {
      final List<List<String>> lines = linesOf(await _rowsOf(loads, verb));
      for (final List<String> cells in lines) {
        expect(cells, hasLength(3), reason: verb);
        for (final String cell in cells) {
          expect(cell, isNot(contains(_control)), reason: verb);
        }
      }
      expect(
        [
          for (final List<String> cells in lines) [...cells.map(_read)],
        ],
        [
          ['name', 'outcome', 'detail'],
          ...rows,
        ],
        reason: verb,
      );
    }
  });
}

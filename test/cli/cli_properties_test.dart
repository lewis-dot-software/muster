import 'dart:convert';

import 'package:glados/glados.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/cli/cli.dart';
import 'package:muster/src/cli/exit_code.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/lock_outcome.dart';
import 'package:muster/src/model/lock_removal.dart';
import 'package:muster/src/model/quoted.dart';

import '../support/fixed_loads.dart';
import '../support/lines_of.dart';
import '../support/outcome_anys.dart';
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

/// The rows a lock giving [outcomes] and [removals] prints: one per lock
/// written, per codebase whose lock failed and per removal.
int _lockRows(Iterable<LockOutcome> outcomes, List<LockRemoval> removals) =>
    removals.length +
    outcomes
        .map(
          (LockOutcome outcome) => switch (outcome) {
            LocksWritten(:final locks) => locks.length,
            LockFailed() => 1,
          },
        )
        .fold(0, (int rows, int more) => rows + more);

/// Every control character, a tab among them, and Unicode's line breaks.
final RegExp _control = .new(r'[\x00-\x1f\x7f-\x9f\u2028\u2029]');

/// What [loads] writes to its rows' sink for [verb].
Future<String> _rowsOf(FixedLoads loads, String verb) async {
  final StringBuffer out = .new();
  await Cli(loads, out, StringBuffer()).run([verb]);
  return '$out';
}

void main() {
  Glados2(
    any.list(any.outcome),
    any.intInRange(-RefusalCase.every.length, RefusalCase.every.length),
  ).test(
    '`muster fetch` prints one row for each codebase, its name, its outcome '
    "and that outcome's own detail, and exits non-zero when any outcome is "
    'not `Fetched` or the load is refused.',
    (List<(GitCodebase, FetchOutcome)> drawn, int refusal) async {
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
        expect('$err', isNotEmpty);
        expect(code.code, isNot(0));
        return;
      }
      expect(
        [
          for (final List<String> cells in linesOf('$out'))
            switch (cells) {
              [final String name, final String outcome, final String detail] =>
                [name, outcome, _read(detail)],
              _ => cells,
            },
        ],
        [
          ['name', 'outcome', 'detail'],
          for (final MapEntry(
                key: CodebaseName name,
                value: FetchOutcome outcome,
              )
              in outcomes.entries)
            [name.name, '${outcome.runtimeType}', _detail(outcome)],
        ],
      );
      expect(
        code.code == 0,
        outcomes.values.every(
          (FetchOutcome o) => switch (o) {
            Fetched() => true,
            FetchFailure() => false,
          },
        ),
      );
    },
  );

  Glados3(
    any.list(any.outcome),
    any.list(any.lockOutcome),
    any.list(any.removal),
  ).test("Every row `muster fetch` and `muster lock` print holds its header's "
      'cells, each one line with no tab, whatever a URL, a path or a command '
      'carries.', (
    List<(GitCodebase, FetchOutcome)> fetchedDrawn,
    List<(GitCodebase, LockOutcome)> lockedDrawn,
    List<LockRemoval> removals,
  ) async {
    final Map<CodebaseName, FetchOutcome> fetched = {
      for (final (GitCodebase codebase, FetchOutcome outcome) in fetchedDrawn)
        codebase.name: outcome,
    };
    final Map<CodebaseName, LockOutcome> locked = {
      for (final (GitCodebase codebase, LockOutcome outcome) in lockedDrawn)
        codebase.name: outcome,
    };
    for (final (String verb, FixedLoads loads, int rows) in [
      ('fetch', FixedLoads.loading(fetched), fetched.length),
      (
        'lock',
        FixedLoads(locks: Locked(locked, removals)),
        _lockRows(locked.values, removals),
      ),
    ]) {
      final List<List<String>> lines = linesOf(await _rowsOf(loads, verb));
      expect(lines, hasLength(rows + 1), reason: verb);
      for (final List<String> cells in lines) {
        expect(cells, hasLength(3), reason: verb);
        for (final String cell in cells) {
          expect(cell, isNot(contains(_control)), reason: verb);
        }
      }
    }
  });
}

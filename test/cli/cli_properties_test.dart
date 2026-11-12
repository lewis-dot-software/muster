import 'package:glados/glados.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/cli/cli.dart';
import 'package:muster/src/cli/exit_code.dart';
import 'package:muster/src/model/git_codebase.dart';

import '../support/fixed_loads.dart';
import '../support/outcome_anys.dart';
import '../support/refusal_case.dart';

/// The detail an outcome's row carries, read off the outcome by its case.
String _detail(FetchOutcome outcome) => switch (outcome) {
  Fetched(:final package) => package.path,
  Unlocked(:final lock) => lock.path,
  CommandFailed(:final command) => [
    command.executable.name,
    ...command.arguments,
  ].join(' '),
  Unstartable(:final executable) => executable.name,
  StoreFailed(:final String path) => path,
  PinMissing(:final commit) => commit.hash,
};

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
      expect('$out'.split('\n'), [
        'name\toutcome\tdetail',
        for (final MapEntry(key: CodebaseName name, value: FetchOutcome outcome)
            in outcomes.entries)
          '${name.name}\t${outcome.runtimeType}\t${_detail(outcome)}',
        '',
      ]);
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
}

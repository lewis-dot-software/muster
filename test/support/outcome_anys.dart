import 'package:glados/glados.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/package.dart';

import 'manifests.dart';
import 'outcome_case.dart';

/// The generators the command line's property tests draw from.
extension OutcomeAnys on Any {
  /// A codebase beside the outcome a load gave it, of any [OutcomeCase].
  Generator<(GitCodebase, FetchOutcome)> get outcome => combine6(
    gitCodebase(),
    choose(OutcomeCase.values),
    intInRange(1, 256),
    choose(['', 'fatal: no such repo\n', 'a\nb']),
    choose(Package.values),
    choose(Executable.values),
    (
      GitCodebase codebase,
      OutcomeCase kind,
      int exitCode,
      String output,
      Package package,
      Executable executable,
    ) => (
      codebase,
      kind.outcome(
        codebase,
        exitCode: exitCode,
        output: output,
        package: package,
        executable: executable,
      ),
    ),
  );
}

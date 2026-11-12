import 'package:muster/muster.dart';
import 'package:test/test.dart';

import 'manifests.dart';
import 'outcome_case.dart';

void main() {
  test('every case makes an outcome of its own case', () {
    for (final OutcomeCase kind in OutcomeCase.values) {
      final FetchOutcome outcome = kind.outcome(
        codebase('app', '/srv/app.git', 'a' * 40, '.', .dart),
        exitCode: 1,
        output: 'out',
        package: .root,
        executable: .git,
      );
      expect(OutcomeCase.of(outcome), kind);
    }
  });
}

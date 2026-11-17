import 'package:muster/src/model/command.dart';
import 'package:muster/src/model/fetch_outcome.dart';
import 'package:muster/src/store/ran.dart';
import 'package:test/test.dart';

import 'faults.dart';
import 'spy_runner.dart';

void main() {
  const Command command = (executable: .git, arguments: ['muster-answered']);

  /// A spy that answers every command it is given with an exit of [exitCode].
  SpyRunner answering(int exitCode) =>
      .new(const {})
        ..answer = (Command _) =>
            (exitCode: exitCode, stdout: 'out', stderr: 'err');

  test('an answer whose exit code is one of the exits is what it '
      'returns', () async {
    final Ran ran = await answering(1).run(command, exits: const {0, 1});
    expect(ran, (exitCode: 1, stdout: 'out', stderr: 'err'));
  });

  test('an answer whose exit code is none of the exits fails as a run does, '
      'carrying the command, its exit code and its output', () async {
    await expectLater(
      answering(1).run(command),
      throwsA(
        storeFault(
          isA<CommandFailed>()
              .having((CommandFailed f) => f.command, 'command', command)
              .having((CommandFailed f) => f.exitCode, 'exitCode', 1)
              .having((CommandFailed f) => f.stdout, 'stdout', 'out')
              .having((CommandFailed f) => f.stderr, 'stderr', 'err'),
        ),
      ),
    );
  });
}

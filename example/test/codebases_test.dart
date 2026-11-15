import 'dart:io';

import 'package:muster/muster.dart';
import 'package:test/test.dart';

void main() {
  test('every codebase muster.yaml names loads at its pin, resolved', () async {
    switch (await Muster.load()) {
      case Refused(:final LoadRefusal reason):
        fail('The load refused: $reason');
      case Loaded(:final Map<CodebaseName, FetchOutcome> outcomes):
        for (final MapEntry(key: CodebaseName name, value: FetchOutcome outcome)
            in outcomes.entries) {
          switch (outcome) {
            case Fetched(:final PackagePath package, :final SdkVersion sdk):
              // Hand package.path to the tool under test.
              expect(File(package.packageConfig.path).existsSync(), isTrue);
              print('${name.name} at ${package.path}, resolved by $sdk');
            case Unlocked(:final KeptLockPath lock):
              fail(
                '${name.name} has no lock: run `dart run muster lock` '
                'to write ${lock.path}',
              );
            case CommandFailed(:final Command command, :final String stderr):
              fail(
                '${name.name}: ${command.executable.name} '
                '${command.arguments.join(' ')} failed\n$stderr',
              );
            case Unstartable(:final Executable executable):
              fail('${name.name}: ${executable.name} is not on PATH');
            case StoreFailed(:final String path, :final String reason):
              fail('${name.name}: $path: $reason');
            case PinMissing(:final GitUrl url, :final Commit commit):
              fail('${name.name}: ${commit.hash} is not in ${url.url}');
          }
        }
    }
  });
}

import 'dart:io';

import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/loads.dart';
import '../support/origin.dart';
import '../support/packages.dart';

/// A consumer's test that loads every codebase its manifests name and fails
/// on any outcome but `Fetched`, each package's pubspec its own and its
/// `package_config.json` written.
const String _consumerTest = r'''
import 'dart:io';

import 'package:muster/muster.dart';
import 'package:test/test.dart';

void main() {
  test('every codebase is fetched', () async {
    switch (await Muster.load()) {
      case Refused(:final LoadRefusal reason):
        fail('refused: $reason');
      case Loaded(:final Map<CodebaseName, FetchOutcome> outcomes):
        expect([for (final CodebaseName n in outcomes.keys) n.name], [
          'app',
          'bench',
        ]);
        for (final MapEntry(key: CodebaseName name, value: FetchOutcome outcome)
            in outcomes.entries) {
          switch (outcome) {
            case Fetched(:final PackagePath package):
              expect(
                File('${package.path}/pubspec.yaml').readAsStringSync(),
                startsWith('name: ${name.name}\n'),
              );
              expect(File(package.packageConfig.path).existsSync(), isTrue);
            case FetchFailure():
              fail('$outcome');
          }
        }
    }
  });
}
''';

void main() {
  test("a consumer's dart test gets every git codebase its muster.yaml and "
      'MUSTER_MANIFESTS name at its pin, resolved, with no setup', () async {
    await inTemp((Directory temp) async {
      final Map<String, String> environment = hermetic(temp);
      final Runner runner = .new(environment);
      final Origin origin = await .make(temp, runner);
      final Commit app = await origin.commit(null, packageFiles('app'));
      final Commit bench = await origin.commit(
        null,
        packageFiles('bench', locked: false),
      );
      await origin.ref('refs/heads/main', app);
      await origin.ref('refs/heads/bench', bench);
      final GitCodebase benchCodebase = codebaseOf(
        origin,
        bench,
        name: 'bench',
      );
      final String second = p.join(temp.path, 'elsewhere', 'bench.yaml');
      await writeManifest(atRoot(temp), [codebaseOf(origin, app)]);
      await writeManifest(second, [benchCodebase]);
      final KeptLockPath kept = .of(locksBeside(second), benchCodebase, .root);
      await File(kept.path).create(recursive: true);
      await File(kept.path).writeAsString(lockText);
      final String muster = await musterRoot();
      final String consumer = consumerIn(temp).path;
      await File(p.join(consumer, 'pubspec.yaml')).writeAsString(
        'name: consumer\n'
        'environment:\n  sdk: ^3.13.0\n'
        'dev_dependencies:\n'
        '  muster:\n    path: $muster\n'
        '  test: any\n',
      );
      await File(p.join(consumer, 'test', 'bench_test.dart'))
          .create(recursive: true)
          .then((File f) => f.writeAsString(_consumerTest));
      final ProcessResult got = await Process.run(
        'dart',
        ['pub', 'get', '--offline'],
        workingDirectory: consumer,
        environment: environment,
      );
      expect(got.exitCode, 0, reason: '${got.stdout}${got.stderr}');
      final ProcessResult tested = await Process.run(
        'dart',
        ['test'],
        workingDirectory: consumer,
        environment: {
          ...loadEnvironment(temp).variables,
          'MUSTER_MANIFESTS': second,
        },
      );
      expect(tested.exitCode, 0, reason: '${tested.stdout}${tested.stderr}');
    });
  });
}

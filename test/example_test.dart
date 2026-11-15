import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/files_under.dart';
import 'support/git.dart';
import 'support/loads.dart';
import 'support/write_file.dart';

/// The example's own `dart test`, the README's manifest and test, run on a
/// copy of the example in a temporary directory with a cache of its own, so
/// no checkout or clone stands and its codebases are fetched as a stranger's
/// first run fetches them: equatable cloned from GitHub, and `path` unpacked
/// from pub.dev through the user's pub cache.
void main() {
  test("The example's test loads every codebase its manifest names at its "
      'pin, resolved, with no setup.', () async {
    await inTemp((Directory temp) async {
      final String muster = await musterRoot();
      final String example = p.join(temp.path, 'example');
      final Map<String, String> files = await filesUnder(
        p.join(muster, 'example'),
        less: ['.dart_tool', 'pubspec.yaml'],
      );
      for (final MapEntry(key: String path, value: String text)
          in files.entries) {
        await writeFile(p.joinAll([example, ...p.posix.split(path)]), text);
      }
      // The example's own pubspec resolves it in muster's workspace, which a
      // copy outside the repo has no way into.
      await writeFile(
        p.join(example, 'pubspec.yaml'),
        'name: muster_example\n'
        'environment:\n  sdk: ^3.13.0\n'
        'dev_dependencies:\n'
        '  muster:\n    path: $muster\n'
        '  test: any\n',
      );
      final Map<String, String> environment = {
        ...hermetic(temp)..remove('MUSTER_MANIFESTS'),
        'MUSTER_CACHE': p.join(temp.path, 'cache'),
      };
      final ProcessResult got = await Process.run(
        'dart',
        ['pub', 'get', '--offline'],
        workingDirectory: example,
        environment: environment,
      );
      expect(got.exitCode, 0, reason: '${got.stdout}${got.stderr}');
      final ProcessResult tested = await Process.run(
        'dart',
        ['test'],
        workingDirectory: example,
        environment: environment,
      );
      expect(tested.exitCode, 0, reason: '${tested.stdout}${tested.stderr}');
      expect(
        Directory(p.join(temp.path, 'cache')).listSync(),
        isNotEmpty,
        reason: 'equatable was cloned into the cache',
      );
    });
  });
}

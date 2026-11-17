import 'dart:io';

import 'package:test/test.dart';

import '../support/git.dart';
import '../support/loads.dart';

void main() {
  test('`dart doc` warns of nothing in the API docs pub.dev shows.', () async {
    await inTemp((Directory temp) async {
      // Its output goes to the temporary directory, so no run of the suite
      // leaves `doc/api/` in the repo.
      final ProcessResult documented = await Process.run('dart', [
        'doc',
        '--dry-run',
        '--output',
        temp.path,
      ], workingDirectory: await musterRoot());
      final String said = '${documented.stdout}${documented.stderr}';
      expect(documented.exitCode, 0, reason: said);
      expect(said, contains('Found 0 warnings and 0 errors.'));
    });
  });
}

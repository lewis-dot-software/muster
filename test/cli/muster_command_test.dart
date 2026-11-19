import 'dart:io';

import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/host.dart';
import '../support/loads.dart';
import '../support/origin.dart';
import '../support/packages.dart';

void main() {
  late Directory temp;
  late String consumer;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    consumer = consumerIn(temp).path;
    await Directory(consumer).create(recursive: true);
  });

  tearDown(() => temp.delete(recursive: true));

  /// `muster` run with [arguments] in the consumer's root, its cache in the
  /// test's own directory.
  Future<ProcessResult> muster(List<String> arguments) async => Process.run(
    Platform.resolvedExecutable,
    [p.join(await musterRoot(), 'bin', 'muster.dart'), ...arguments],
    workingDirectory: consumer,
    environment: loadEnvironment(temp).variables,
    includeParentEnvironment: false,
  );

  test('the muster command locks then fetches a git codebase that holds no '
      'lock of its own, exiting 0 with its row Fetched', () async {
    final Origin origin = await .make(temp, .new(hermetic(temp), host));
    final Commit pin = await origin.commit(
      null,
      packageFiles('app', locked: false),
    );
    await origin.ref('refs/heads/main', pin);
    final GitCodebase app = codebaseOf(origin, pin);
    await writeManifest(atRoot(temp), [app]);
    final ProcessResult locked = await muster(['lock']);
    expect(locked.exitCode, 0, reason: '${locked.stderr}');
    final ProcessResult fetched = await muster(['fetch']);
    expect(fetched.exitCode, 0, reason: '${fetched.stderr}');
    expect(
      fetched.stdout,
      'name\toutcome\tdetail\n'
      'app\tFetched\t${p.join(await Directory(consumer).resolveSymbolicLinks(), '.dart_tool', 'muster', 'app')}\n',
    );
  });

  test('the muster command exits 2 on a refused run, naming the working '
      'directory it sought muster.yaml in, and 64 on a command line it does '
      'not take', () async {
    final ProcessResult refused = await muster(['fetch']);
    expect(refused.exitCode, 2);
    expect(
      refused.stderr,
      'no manifest: none named, no muster.yaml at '
      '${await Directory(consumer).resolveSymbolicLinks()}, and none in '
      'MUSTER_MANIFESTS\n',
    );
    expect((await muster(['nope'])).exitCode, 64);
  });

  test("the muster command writes its rows alone to standard output, and "
      "nothing to standard error, for a manifest opening on a directive the "
      "YAML reader warns of", () async {
    await File(atRoot(temp)).writeAsString('%FOO bar\n---\ncodebases: {}\n');
    for (final String verb in ['fetch', 'lock']) {
      final ProcessResult run = await muster([verb]);
      expect(run.exitCode, 0, reason: verb);
      expect(run.stdout, 'name\toutcome\tdetail\n', reason: verb);
      expect(run.stderr, isEmpty, reason: verb);
    }
  });
}

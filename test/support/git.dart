import 'dart:io';

import 'package:muster/src/model/commit.dart';
import 'package:muster/src/store/cache.dart';
import 'package:muster/src/store/ran.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;

/// A directory of a test's own, deleted when [body] is done with it.
Future<T> inTemp<T>(Future<T> Function(Directory temp) body) async {
  final Directory temp = await .systemTemp.createTemp('muster-');
  try {
    return await body(temp);
  } finally {
    await temp.delete(recursive: true);
  }
}

/// The environment a test's git runs under, in [temp]: the test process's
/// own, with no user's or system's configuration read, and an author and
/// committer named, so a fixture's commits stand alike on every machine.
Map<String, String> hermetic(Directory temp) {
  final File config = .new(p.join(temp.path, 'gitconfig'))..createSync();
  return {
    ...Platform.environment,
    'GIT_CONFIG_GLOBAL': config.path,
    'GIT_CONFIG_NOSYSTEM': '1',
    'GIT_AUTHOR_NAME': 'muster',
    'GIT_AUTHOR_EMAIL': 'muster@example.com',
    'GIT_COMMITTER_NAME': 'muster',
    'GIT_COMMITTER_EMAIL': 'muster@example.com',
  };
}

/// A cache in [temp], its git run by [runner].
Cache cacheIn(Directory temp, Runner runner) => .new(
  .of((variables: {'MUSTER_CACHE': p.join(temp.path, 'cache')}, os: .posix))!,
  runner,
);

/// Whether the repo at [gitDir] holds [commit] as a commit, read by [runner].
Future<bool> holds(String gitDir, Commit commit, Runner runner) async {
  final Ran ran = await runner.run(
    (
      executable: .git,
      arguments: ['--git-dir=$gitDir', 'cat-file', '-t', commit.hash],
    ),
    exits: const {0, 128},
  );
  return ran.exitCode == 0 && ran.stdout.trim() == 'commit';
}

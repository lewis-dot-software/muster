import 'dart:io';

import 'package:muster/src/model/clone_path.dart';
import 'package:muster/src/store/ran.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;

import 'loads.dart';

/// Every file under [directory], from its top in `/` separators, beside its
/// contents, less any `.git`.
Future<Map<String, String>> filesUnder(String directory) async => {
  await for (final FileSystemEntity entity in Directory(
    directory,
  ).list(recursive: true, followLinks: false))
    if (entity is File)
      if (p.posix.joinAll(p.split(p.relative(entity.path, from: directory)))
          case final String path
          when path != '.git' && !path.startsWith('.git/'))
        path: await entity.readAsString(),
};

/// The commit `HEAD` names in the worktree at [worktree], read by [runner].
Future<String> headOf(String worktree, Runner runner) async {
  final Ran ran = await runner.run((
    executable: .git,
    arguments: ['-C', worktree, 'rev-parse', 'HEAD'],
  ));
  return ran.stdout.trim();
}

/// The worktrees [clone] keeps a record of, less the clone itself, each
/// with its symbolic links resolved where it is there, read by [runner].
Future<List<String>> worktreesOf(ClonePath clone, Runner runner) async {
  final Ran ran = await runner.run((
    executable: .git,
    arguments: ['--git-dir=${clone.path}', 'worktree', 'list', '--porcelain'],
  ));
  final List<String> listed = [
    for (final String line in ran.stdout.split('\n'))
      if (line.startsWith('worktree ')) line.substring('worktree '.length),
  ];
  return [
    for (final String path in listed.skip(1))
      await Directory(path).exists()
          ? await Directory(path).resolveSymbolicLinks()
          : path,
  ];
}

/// The checkout of the codebase [name] in [temp], its symbolic links
/// resolved, as [worktreesOf] reads it.
Future<String> resolvedCheckout(Directory temp, String name) =>
    Directory(checkoutAt(temp, name)).resolveSymbolicLinks();

/// Every directory a scratch of a test's load in [temp] leaves in its
/// temporary directory.
Future<List<String>> scratchesLeft(Directory temp) async {
  final Directory scratches = .new(scratchesIn(temp).path);
  if (!await scratches.exists()) {
    return [];
  }
  return [
    await for (final FileSystemEntity entity in scratches.list()) entity.path,
  ];
}

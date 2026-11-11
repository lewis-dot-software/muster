import 'dart:io';

import '../model/cache_directory.dart';
import '../model/clone_path.dart';
import '../model/commit.dart';
import '../model/fetch_outcome.dart';
import '../model/git_url.dart';
import 'file_act.dart';
import 'git_on.dart';
import 'ran.dart';
import 'runner.dart';
import 'store_fault.dart';

/// The cache's clones, one bare clone a git URL with its whole history, made
/// and fetched through a [Runner].
class Cache {
  /// The clones in [directory], their git run by [runner].
  Cache(this.directory, this._runner);

  /// The directory the clones stand in.
  final CacheDirectory directory;

  final Runner _runner;

  /// The clone of [url], holding [pin]: cloned where the cache has none, then
  /// fetched, every branch and tag, only where it lacks [pin], each ref the
  /// URL no longer has pruned, so a branch deleted there never blocks one
  /// named under it.
  ///
  /// A new clone is made under a temporary name and moved into place, so a
  /// clone that fails leaves nothing in the cache and one cut short leaves
  /// only a directory no call reads, and takes its
  /// object format from [url]'s repo. A URL that is a path is cloned as any
  /// other is, so the clone holds what its branches and tags reach alone.
  ///
  /// Throws a [StoreFault] of [PinMissing] where the fetch leaves the clone
  /// lacking [pin], of [CommandFailed] or [Unstartable] where git fails, and
  /// of [StoreFailed] where a file act does.
  Future<ClonePath> clone(GitUrl url, Commit pin) async {
    final ClonePath clone = .of(directory, url);
    if (!await fileAct(clone.path, Directory(clone.path).exists)) {
      await _make(clone, url);
    }
    if (await _holds(clone, pin)) {
      return clone;
    }
    await _runner.run(
      gitOn(clone, ['fetch', '--prune', url.url, ..._everyBranchAndTag]),
    );
    if (await _holds(clone, pin)) {
      return clone;
    }
    throw StoreFault(PinMissing(url, pin));
  }

  Future<void> _make(ClonePath clone, GitUrl url) async {
    final Directory made = await fileAct(directory.path, () async {
      final Directory cache = await .new(
        directory.path,
      ).create(recursive: true);
      return cache.createTemp('.clone-');
    });
    try {
      await _runner.run((
        executable: .git,
        arguments: [
          'clone',
          '--quiet',
          '--bare',
          '--no-local',
          url.url,
          made.path,
        ],
      ));
      await fileAct(made.path, () => made.rename(clone.path));
    } on StoreFault {
      try {
        await made.delete(recursive: true);
      } on FileSystemException {
        // The clone's own failure is the one its caller acts on. A directory
        // the removal leaves is one no call reads, as a clone cut short
        // leaves, for the cache's sweep of temporary clones to take.
      }
      rethrow;
    }
  }

  /// Whether [clone] holds [pin] as a commit. A hash git peels to another, as
  /// it does an annotated tag's, is held by no commit.
  Future<bool> _holds(ClonePath clone, Commit pin) async {
    final Ran ran = await _runner.run(
      gitOn(clone, [
        'rev-parse',
        '--verify',
        '--quiet',
        '--end-of-options',
        '${pin.hash}^{commit}',
      ]),
      exits: const {0, 1},
    );
    return ran.exitCode == 0 && ran.stdout.trim() == pin.hash;
  }
}

/// The refspecs a fetch carries, since a bare clone keeps none of its own.
const List<String> _everyBranchAndTag = [
  '+refs/heads/*:refs/heads/*',
  '+refs/tags/*:refs/tags/*',
];

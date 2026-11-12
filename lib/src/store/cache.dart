import 'dart:io';

import '../model/cache_directory.dart';
import '../model/clone_path.dart';
import '../model/commit.dart';
import '../model/fetch_outcome.dart';
import '../model/git_url.dart';
import '../model/temporary_clone_path.dart';
import 'claims.dart';
import 'file_act.dart';
import 'git_on.dart';
import 'ran.dart';
import 'runner.dart';
import 'store_fault.dart';

/// The cache's clones, one bare clone a git URL with its whole history, made
/// and fetched through a [Runner], each temporary clone left by a make cut
/// short removed once no load holds its clone's claim in [Claims].
class Cache {
  /// The clones in [directory], their git run by [_runner], and the claims
  /// on them tried in [_claims].
  Cache(this.directory, this._runner, this._claims);

  /// The directory the clones stand in.
  final CacheDirectory directory;

  final Runner _runner;

  final Claims _claims;

  /// The clone of [url], holding [pin]: cloned where the cache has none, then
  /// fetched, every branch and tag, only where it lacks [pin], each ref the
  /// URL no longer has pruned, so a branch deleted there never blocks one
  /// named under it. Its caller holds the claim on [url]'s clone.
  ///
  /// A new clone is made in its temporary clone and moved into place, so a
  /// clone that fails leaves nothing in the cache, and takes its object
  /// format from [url]'s repo. A URL that is a path is cloned as any other
  /// is, so the clone holds what its branches and tags reach alone.
  ///
  /// Every temporary clone in the cache is removed first, [url]'s own and
  /// each other whose clone's claim no other hold has, so one left by a make
  /// cut short goes at the next call. One whose claim is held, a make's in
  /// flight, is left to it, and never waited on.
  ///
  /// Throws a [StoreFault] of [PinMissing] where the fetch leaves the clone
  /// lacking [pin], of [CommandFailed] or [Unstartable] where git fails, and
  /// of [StoreFailed] where a file act does, a removal or a claim's among
  /// them.
  Future<ClonePath> clone(GitUrl url, Commit pin) async {
    final ClonePath clone = .of(directory, url);
    await _sweep(clone);
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

  /// Removes every temporary clone in the cache whose clone's claim no other
  /// hold has, and [own]'s, whose claim the caller holds.
  Future<void> _sweep(ClonePath own) async {
    final List<ClonePath> left = await fileAct(directory.path, () async {
      final Directory cache = .new(directory.path);
      if (!await cache.exists()) {
        return const [];
      }
      return [
        await for (final FileSystemEntity entity in cache.list())
          if (ClonePath.ofTemporary(
                directory,
                directory.os.paths.basename(entity.path),
              )
              case final ClonePath clone)
            clone,
      ];
    });
    for (final ClonePath clone in left) {
      if (clone == own) {
        await _remove(clone.temporary);
      } else {
        await _claims.holdingIfFree(
          clone.claim,
          () => _remove(clone.temporary),
        );
      }
    }
  }

  /// Removes [temporary], where it is there.
  Future<void> _remove(TemporaryClonePath temporary) =>
      fileAct(temporary.path, () async {
        final Directory directory = .new(temporary.path);
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

  Future<void> _make(ClonePath clone, GitUrl url) async {
    final TemporaryClonePath temporary = clone.temporary;
    final Directory made = await fileAct(
      temporary.path,
      () => Directory(temporary.path).create(recursive: true),
    );
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
        // The clone's own failure is the one its caller acts on. A temporary
        // clone the removal leaves goes at the cache's next clone.
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

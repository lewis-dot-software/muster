import 'dart:io';

import '../model/clone_path.dart';
import '../model/commit.dart';
import '../model/fetch_outcome.dart';
import '../model/git_codebase.dart';
import '../model/scratch_path.dart';
import '../model/temp_directory.dart';
import 'add_worktree.dart';
import 'cache.dart';
import 'claims.dart';
import 'file_act.dart';
import 'git_on.dart';
import 'move_worktree.dart';
import 'remove_directory.dart';
import 'runner.dart';
import 'store_fault.dart';

/// Scratches, each a worktree of a clone in a [Cache] made in a temporary
/// directory of its own, for a consumer to move as it likes, their git run
/// by a [Runner] and their acts on a clone held under [Claims].
class Scratches {
  /// The scratches of the clones in [_cache], each made in a directory of
  /// its own under [_temp], their git run by [_runner], and every act on a
  /// clone held under its claim in [_claims].
  Scratches(this._cache, this._runner, this._claims, this._temp);

  final Cache _cache;

  final Runner _runner;

  final Claims _claims;

  final TempDirectory _temp;

  /// A new scratch of [codebase] at its pin: a worktree of its clone, cloned
  /// where the cache has none and fetched where it lacks the pin, added in a
  /// new directory under the temporary directory.
  ///
  /// The clone's claim is held from before the clone is touched until the
  /// worktree is added, and the clone's worktrees pruned first, so one whose
  /// directory was deleted by hand never blocks it. A scratch that cannot be
  /// made removes the directory it made, and a directory the removal itself
  /// fails on is left to the system's sweep of its temporary directory.
  ///
  /// Throws a [StoreFault] of [PinMissing] where the clone cannot reach the
  /// pin, of [CommandFailed] or [Unstartable] where git fails, and of
  /// [StoreFailed] where a file act does, a claim's among them.
  Future<ScratchPath> make(GitCodebase codebase) async {
    final Directory made = await fileAct(_temp.path, () async {
      final Directory temp = await .new(_temp.path).create(recursive: true);
      return temp.createTemp('muster-scratch-');
    });
    final ScratchPath at = .new(made.path, _temp.os);
    try {
      await _holdingClone(codebase, () async {
        final ClonePath clone = await _cache.clone(
          codebase.url,
          codebase.commit,
        );
        await addWorktree(_runner, clone, at, codebase.commit);
      });
    } on StoreFault {
      try {
        await removeDirectory(made.path);
      } on StoreFault {
        // The make's own failure is the one its caller acts on. A directory
        // the removal leaves is one the system's sweep of its temporary
        // directory takes.
      }
      rethrow;
    }
    return at;
  }

  /// The scratch at [scratch], of [codebase], moved to [commit], holding its
  /// tracked files alone, every edit reverted and every file it lacks
  /// removed. The clone is fetched first, under its claim, where it lacks
  /// [commit].
  ///
  /// Throws a [StoreFault] of [PinMissing] where the clone cannot reach
  /// [commit], of [CommandFailed] or [Unstartable] where git fails, and of
  /// [StoreFailed] where a file act does, a claim's among them.
  Future<void> move(
    ScratchPath scratch,
    GitCodebase codebase,
    Commit commit,
  ) async {
    await _holdingClone(codebase, () => _cache.clone(codebase.url, commit));
    await moveWorktree(_runner, scratch, commit);
  }

  /// The scratch at [scratch], of [codebase], removed: its directory
  /// deleted, then its clone's worktrees pruned under the clone's claim, so
  /// the clone keeps no record of it. A scratch already gone is removed with
  /// nothing deleted.
  ///
  /// Throws a [StoreFault] of [CommandFailed] or [Unstartable] where git
  /// fails, and of [StoreFailed] where a file act does, a claim's among them.
  Future<void> remove(ScratchPath scratch, GitCodebase codebase) async {
    await removeDirectory(scratch.path);
    final ClonePath clone = .of(_cache.directory, codebase.url);
    if (!await fileAct(clone.path, Directory(clone.path).exists)) {
      return;
    }
    await _holdingClone(
      codebase,
      () => _runner.run(gitOn(clone, ['worktree', 'prune'])),
    );
  }

  /// [act] run holding the claim on [codebase]'s clone.
  Future<T> _holdingClone<T>(GitCodebase codebase, Future<T> Function() act) =>
      _claims.holding(ClonePath.of(_cache.directory, codebase.url).claim, act);
}

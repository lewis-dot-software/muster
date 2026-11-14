import '../model/commit.dart';
import '../model/disposal.dart';
import '../model/git_codebase.dart';
import '../model/move.dart';
import '../model/package_path.dart';
import '../model/scratch_path.dart';
import '../store/scratches.dart';
import '../store/store_fault.dart';

/// A worktree of a codebase's clone in a temporary directory, a consumer's
/// own to move to any commit, since no load reads it, until it is disposed
/// of.
final class Scratch {
  Scratch._(this._scratches, this._codebase, this._at);

  final Scratches _scratches;

  final GitCodebase _codebase;

  final ScratchPath _at;

  /// The package at the codebase's root, inside the scratch.
  PackagePath get package => packageInScratch(_at, _codebase.root);

  /// Moves the scratch to [commit], holding that commit's tracked files
  /// alone: every tracked file's edit reverted and every other file removed,
  /// ignored ones among them, the clone fetched first where it lacks
  /// [commit]. No checkout of any consumer's is touched.
  ///
  /// Returns [Moved], or [MoveFailed] with why. Nothing throws but a bug.
  Future<Move> move(Commit commit) async {
    try {
      await _scratches.move(_at, _codebase, commit);
      return const Moved();
    } on StoreFault catch (fault) {
      return MoveFailed(fault.act);
    }
  }

  /// Removes the scratch, its directory and its clone's record of it, so
  /// nothing of it is left. A scratch disposed of already is disposed of
  /// again with nothing to remove.
  ///
  /// Returns [Disposed], or [DisposalFailed] with why. Nothing throws but a
  /// bug.
  Future<Disposal> dispose() async {
    try {
      await _scratches.remove(_at, _codebase);
      return const Disposed();
    } on StoreFault catch (fault) {
      return DisposalFailed(fault.act);
    }
  }
}

/// The scratch at [at], of [codebase], moved and removed through
/// [scratches].
Scratch scratchOf(Scratches scratches, GitCodebase codebase, ScratchPath at) =>
    ._(scratches, codebase, at);

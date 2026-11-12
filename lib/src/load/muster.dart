import '../model/codebase_name.dart';
import '../model/git_codebase.dart';
import '../model/scratch_path.dart';
import '../store/scratches.dart';
import '../store/store_fault.dart';
import 'load.dart';
import 'process_loads.dart';
import 'scratching.dart';

/// muster's entry: the load of a consumer's codebases, and the scratches a
/// consumer moves off their pins.
final class Muster {
  /// The muster that makes a scratch of each of [_codebases], by its name,
  /// through [_scratches].
  Muster(this._codebases, this._scratches);

  final Map<CodebaseName, GitCodebase> _codebases;

  final Scratches _scratches;

  /// Brings every codebase the consumer's manifests name to its pin in a
  /// checkout under [root], resolved, and gives each its outcome.
  ///
  /// The manifests are the [manifests] given where any is, and else the
  /// `muster.yaml` at [root] and every path `MUSTER_MANIFESTS` lists. [root]
  /// is the working directory where it is left out, and a relative path,
  /// [root] among them, is read against the working directory.
  ///
  /// The environment, the system, the working directory and the temporary
  /// directory are read once, here, and every process the load and its
  /// scratches start runs with that environment alone.
  ///
  /// Returns [Refused] where muster takes no claim on the system, the
  /// manifests refuse the load, the working directory cannot be read or no
  /// cache is named, before any process
  /// starts or any file is written, and [Loaded] otherwise, every failure a
  /// codebase meets carried as its outcome. Nothing throws but a bug.
  static Future<Load> load({List<String> manifests = const [], String? root}) =>
      const ProcessLoads().load(named: manifests, root: root);

  /// A new scratch of the codebase [name]: a worktree of its clone at its
  /// pin, in a temporary directory of its own, the consumer's to move to
  /// any commit while every checkout stays at its pin, until it is disposed
  /// of. The clone is cloned or fetched as a load's is where it lacks the
  /// pin, so a scratch is made whatever the codebase's checkout gave.
  ///
  /// Another load or scratch acting on the clone is waited on, never acted
  /// beside.
  ///
  /// Returns [Scratched], [NotNamed] where no codebase of the load bears
  /// [name], and [ScratchFailed] where the scratch cannot be made, its
  /// directory removed. Nothing throws but a bug.
  Future<Scratching> scratch(CodebaseName name) async {
    final GitCodebase? codebase = _codebases[name];
    if (codebase == null) {
      return NotNamed(name);
    }
    try {
      final ScratchPath at = await _scratches.make(codebase);
      return Scratched(.new(_scratches, codebase, at));
    } on StoreFault catch (fault) {
      return ScratchFailed(fault.act);
    }
  }
}

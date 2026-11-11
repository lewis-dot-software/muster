import '../model/environment.dart';
import '../model/fetch_outcome.dart';
import '../model/load_refusal.dart';
import '../model/working_directory.dart';
import '../store/current_directory.dart';
import '../store/process_environment.dart';
import '../store/store_fault.dart';
import 'load.dart';
import 'loader.dart';

/// muster's entry: the load of a consumer's codebases.
abstract final class Muster {
  /// Brings every codebase the consumer's manifests name to its pin in a
  /// checkout under [root], resolved, and gives each its outcome.
  ///
  /// The manifests are the [manifests] given where any is, and else the
  /// `muster.yaml` at [root] and every path `MUSTER_MANIFESTS` lists. [root]
  /// is the working directory where it is left out, and a relative path,
  /// [root] among them, is read against the working directory.
  ///
  /// The environment and the working directory are read once, here, and
  /// every process the load starts runs with that environment alone.
  ///
  /// Returns [Refused] where the manifests refuse the load, the working
  /// directory cannot be read or no cache is named, before any process
  /// starts or any file is written, and [Loaded] otherwise, every failure a codebase meets carried
  /// as its outcome. Nothing throws but a bug.
  static Future<Load> load({
    List<String> manifests = const [],
    String? root,
  }) async {
    final Environment environment = processEnvironment();
    final WorkingDirectory directory;
    try {
      directory = await currentDirectory(environment.os);
    } on StoreFault catch (fault) {
      if (fault.failure case StoreFailed(:final String reason)) {
        return Refused(NoWorkingDirectory(reason));
      }
      rethrow;
    }
    return Loader(
      environment,
      directory,
      .new(environment.variables),
    ).load(named: manifests, root: root);
  }
}

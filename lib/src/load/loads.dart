import 'load.dart';
import 'locking.dart';

/// The two runs over a consumer's manifests: a load, which brings each
/// codebase to its pin, and a lock, which writes the kept locks they lack
/// and removes those none names.
abstract interface class Loads {
  /// Brings each codebase the manifests name to its pin in a checkout under
  /// [root], resolved, the manifests the [named] ones where any is given,
  /// and else the `muster.yaml` at [root] and every one `MUSTER_MANIFESTS`
  /// lists.
  Future<Load> load({List<String> named = const [], String? root});

  /// Writes each kept lock a codebase needs and lacks, its checkout under
  /// the working directory, the manifests read as [load] reads them, and
  /// removes each kept lock and partial no codebase of its manifest names.
  Future<Locking> lock({List<String> named = const []});
}

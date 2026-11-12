import 'load.dart';
import 'locking.dart';

/// The two runs over a consumer's manifests: a load, which brings each
/// codebase to its pin, and a lock, which writes the kept locks they lack.
abstract interface class Loads {
  /// Brings each codebase the manifests name to its pin in a checkout under
  /// [root], resolved, the manifests the [named] ones where any is given,
  /// and else the `muster.yaml` at [root] and every one `MUSTER_MANIFESTS`
  /// lists.
  Future<Load> load({List<String> named = const [], String? root});

  /// Writes each kept lock a codebase of the same manifests needs and
  /// lacks, its checkout under the working directory, and removes each its
  /// manifest no longer names.
  Future<Locking> lock({List<String> named = const []});
}

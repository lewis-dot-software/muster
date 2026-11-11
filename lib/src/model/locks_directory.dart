import 'manifest_path.dart';
import 'os.dart';

/// The directory a manifest keeps its kept locks in.
extension type const LocksDirectory._(({String path, Os os}) _locks) {
  /// The locks of [manifest], beside it in `<stem>_locks/`, the stem its file
  /// name less `.yaml`, so no two manifests share a directory.
  static LocksDirectory beside(ManifestPath manifest) {
    final String name = manifest.os.paths.basename(manifest.path);
    return ._((
      path: manifest.os.paths.join(
        manifest.os.paths.dirname(manifest.path),
        '${name.substring(0, name.length - '.yaml'.length)}_locks',
      ),
      os: manifest.os,
    ));
  }

  /// The directory's path.
  String get path => _locks.path;

  /// The system whose paths the directory, and every lock in it, is written
  /// in.
  Os get os => _locks.os;
}

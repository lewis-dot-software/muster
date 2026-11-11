import 'os.dart';

/// The file of one manifest, and the system whose paths it is written in.
extension type const ManifestPath._(({String path, Os os}) _manifest) {
  /// The manifest at [path], written in [os]'s paths, or null where its file
  /// name does not end `.yaml` after a stem of its own.
  static ManifestPath? parse(String path, Os os) {
    final String name = os.paths.basename(path);
    return name.length > '.yaml'.length && name.endsWith('.yaml')
        ? ._((path: path, os: os))
        : null;
  }

  /// The manifest's path.
  String get path => _manifest.path;

  /// The system whose paths the manifest, and every path beside it, is
  /// written in.
  Os get os => _manifest.os;
}

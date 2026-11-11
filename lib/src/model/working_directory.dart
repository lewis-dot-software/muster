import 'os.dart';

/// The working directory of the process a load runs in, and the system whose
/// paths it is written in.
extension type const WorkingDirectory._(({String path, Os os}) _directory) {
  /// The working directory at [path], written in [os]'s paths.
  WorkingDirectory(String path, Os os) : this._((path: path, os: os));

  /// The directory's path.
  String get path => _directory.path;

  /// The system whose paths the directory is written in.
  Os get os => _directory.os;

  /// [relative] read against the directory, and normalised. A path that is
  /// absolute already is normalised alone.
  String resolve(String relative) =>
      os.paths.normalize(os.paths.join(path, relative));
}

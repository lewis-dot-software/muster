import 'os.dart';

/// The system's directory for temporary files, the one scratches are made
/// in, and the system whose paths it is written in.
extension type const TempDirectory._(({String path, Os os}) _directory) {
  /// The temporary directory at [path], written in [os]'s paths.
  TempDirectory(String path, Os os) : this._((path: path, os: os));

  /// The directory's path.
  String get path => _directory.path;

  /// The system whose paths the directory, and every path under it, is
  /// written in.
  Os get os => _directory.os;
}

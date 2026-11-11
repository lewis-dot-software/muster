import 'os.dart';

/// A consumer's root, the directory its checkouts stand under, and the system
/// whose paths it is written in.
extension type const ConsumerRoot._(({String path, Os os}) _root) {
  /// The root at [path], written in [os]'s paths.
  ConsumerRoot(String path, Os os) : this._((path: path, os: os));

  /// The root's path.
  String get path => _root.path;

  /// The system whose paths the root, and every path under it, is written in.
  Os get os => _root.os;
}

import 'environment.dart';
import 'os.dart';

/// The directory of clones every consumer on a machine shares, and the system
/// whose paths it is written in.
extension type const CacheDirectory._(({String path, Os os}) _directory) {
  /// The cache [environment] names: `MUSTER_CACHE` where it is set, else
  /// `muster` under `XDG_CACHE_HOME` where that is an absolute path, else
  /// `.cache/muster` under `HOME`, and on Windows `muster` under
  /// `LOCALAPPDATA` in place of either. A variable set empty counts as unset.
  ///
  /// Null where none of the variables it would take is set.
  static CacheDirectory? of(Environment environment) {
    final Map<String, String> variables = environment.variables;
    final Os os = environment.os;
    String? set(String name) => switch (variables[name]) {
      null || '' => null,
      final String value => value,
    };
    CacheDirectory at(String path) => ._((path: path, os: os));
    if (set('MUSTER_CACHE') case final String cache) {
      return at(cache);
    }
    switch (os) {
      case .windows:
        return switch (set('LOCALAPPDATA')) {
          final String local => at(os.paths.join(local, 'muster')),
          null => null,
        };
      case .posix:
        if (set('XDG_CACHE_HOME') case final String xdg
            when os.paths.isAbsolute(xdg)) {
          return at(os.paths.join(xdg, 'muster'));
        }
        return switch (set('HOME')) {
          final String home => at(os.paths.join(home, '.cache', 'muster')),
          null => null,
        };
    }
  }

  /// The directory's path.
  String get path => _directory.path;

  /// The system whose paths the directory, and every path under it, is
  /// written in.
  Os get os => _directory.os;
}

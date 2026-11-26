import 'os.dart';

/// A variable of the environment the cache's directory can be taken from,
/// each weighed on the systems [weighedOn] names.
enum CacheVariable {
  /// `MUSTER_CACHE`, the cache itself, on either system.
  musterCache('MUSTER_CACHE'),

  /// `XDG_CACHE_HOME`, the directory the cache sits in on a POSIX system.
  xdgCacheHome('XDG_CACHE_HOME'),

  /// `HOME`, under whose `.cache` the cache sits on a POSIX system.
  home('HOME'),

  /// `LOCALAPPDATA`, the directory the cache sits in on Windows.
  localAppData('LOCALAPPDATA');

  const CacheVariable(this.variable);

  /// The variable's name in the environment.
  final String variable;

  /// Whether [os] takes the cache from this variable.
  bool weighedOn(Os os) => switch ((this, os)) {
    (.musterCache, _) => true,
    (.xdgCacheHome || .home, .posix) => true,
    (.xdgCacheHome || .home, .windows) => false,
    (.localAppData, .posix) => false,
    (.localAppData, .windows) => true,
  };
}

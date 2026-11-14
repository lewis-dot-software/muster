import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'os.dart';
import 'outside_path.dart';
import 'package_name.dart';
import 'quiet_yaml_node.dart';

/// The first path dependency, in its pubspec's order, that leaves the
/// unpacked package [package] for the example whose `pubspec.yaml` is
/// [pubspec], or null where none does.
///
/// A dependency is read as pub resolves it: its override where one stands,
/// else its entry in `dependencies` or `dev_dependencies`. The overrides are
/// those of the example's [served] `pubspec_overrides.yaml` where it holds
/// `dependency_overrides`, else the pubspec's own, and where no overrides
/// file is served the one muster writes, overriding [package] to its own
/// path. An override with no value stands too, as pub reads it: the host's
/// package at any version. A path leaves the package where, read from
/// `example/` in [os]'s paths, as pub reads it on the system it runs on, it
/// is absolute or climbs above the package's top. Served overrides empty of
/// YAML, as an empty file or one of comments alone is, hold none, as pub
/// reads them. A pubspec or served overrides that are no YAML map else, and
/// an entry pub would refuse, leave nothing outside, since pub's own resolve
/// fails on them.
OutsidePath? examplePathOutside(
  String pubspec,
  String? served,
  PackageName package,
  Os os,
) {
  final Map<Object?, Object?> published = _map(pubspec) ?? const {};
  final Map<Object?, Object?> overrides;
  switch (served) {
    case null:
      overrides = {
        package.name: {'path': '..'},
      };
    case final String served:
      switch (_map(served)) {
        case null:
          return null;
        case final Map<Object?, Object?> file
            when file.containsKey('dependency_overrides'):
          overrides = _section(file, 'dependency_overrides');
        case _:
          overrides = _section(published, 'dependency_overrides');
      }
  }
  final Map<Object?, Object?> dependencies = {
    ..._section(published, 'dependencies'),
    ..._section(published, 'dev_dependencies'),
  };
  for (final Object? name in {...dependencies.keys, ...overrides.keys}) {
    final Object? spec = overrides.containsKey(name)
        ? overrides[name]
        : dependencies[name];
    if ((name, spec) case (final String name, {'path': final String path})
        when _leaves(path, os)) {
      if (PackageName.parse(name) case final PackageName dependency) {
        return (dependency: dependency, path: path);
      }
    }
  }
  return null;
}

/// [text] read as a YAML map, empty where it holds no YAML, as pub reads
/// it, or null where it is none.
Map<Object?, Object?>? _map(String text) {
  try {
    return switch (quietYamlNode(text)) {
      final YamlMap map => map,
      YamlScalar(value: null) => const {},
      _ => null,
    };
  } on YamlException {
    return null;
  }
}

/// The map [yaml] holds at [key], empty where it holds none.
Map<Object?, Object?> _section(Map<Object?, Object?> yaml, String key) =>
    switch (yaml[key]) {
      final Map<Object?, Object?> section => section,
      _ => const {},
    };

/// Whether [path], read from a package's `example/` in [os]'s paths, leaves
/// the package.
bool _leaves(String path, Os os) {
  final p.Context paths = os.paths;
  return paths.isAbsolute(path) ||
      paths.split(paths.normalize(paths.join('example', path))).first == '..';
}

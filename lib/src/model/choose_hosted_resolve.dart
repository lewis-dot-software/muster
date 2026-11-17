import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'hosted_resolve.dart';
import 'os.dart';
import 'outside_path.dart';
import 'package.dart';
import 'package_name.dart';
import 'published_pubspec.dart';
import 'quiet_yaml_node.dart';

/// What a hosted codebase fetching the package [host] does with its
/// [package], whose `pubspec.yaml` holds [pubspec], or null where the
/// package unpacked holds none, beside the `pubspec_overrides.yaml` pub
/// serves there, [served], or null where it serves none.
///
/// The root resolves, held or not, so pub's own resolve fails on a pubspec
/// it lacks or refuses. The example is not held where it has no pubspec,
/// and is left unresolved where the first path dependency of it, in its
/// pubspec's order, leaves the package. It resolves else, so pub's own
/// resolve fails on a pubspec or served overrides that pub refuses.
///
/// Each dependency is read as pub resolves it: its override where one stands,
/// else its entries in `dependencies` and `dev_dependencies`. The overrides are
/// those of the served overrides where they hold `dependency_overrides`, else
/// the pubspec's own, and where none are served the ones muster writes,
/// overriding [host] to its own path. An override with no value stands too, as
/// pub reads it: a hosted dependency at any version, which leaves nothing. A
/// path leaves the package where, read from `example/` in [os]'s paths, as pub
/// reads it on the system it runs on, it is absolute or climbs above the
/// package's top.
///
/// Nothing is left unresolved where pub refuses what it reads to find the
/// example's dependencies, since its own resolve then fails: a pubspec that
/// is no YAML map, its `name` missing or no package name, served overrides
/// that are no YAML map or hold a field but `dependency_overrides`,
/// `resolution` and `workspace`, a section of dependencies pub reads that
/// is no map, and an entry in one whose name is no package name or the
/// example's own, whose version constraint pub cannot read, or whose spec
/// is no version constraint, no map of one source at most beside its
/// `version`, or a `path` or `sdk` source whose description is no string.
/// Empty YAML, as an empty file or one of comments alone is, is a map with
/// no fields, as pub reads it. A dependency name is held to [PackageName],
/// so one that is a word pub reserves for a package's name is refused too.
/// A `git` or `hosted` description is pub's alone to judge, by rules that
/// turn on the example's language version, so muster reads past one.
HostedResolve chooseHostedResolve(
  Package package, {
  required String? pubspec,
  required String? served,
  required PackageName host,
  required Os os,
}) {
  final YamlNode? yaml = switch (pubspec) {
    final String text => _node(text),
    null => null,
  };
  final PublishedPubspec published = switch (yaml) {
    final YamlMap fields => (
      member: fields['resolution'] == 'workspace',
      overrides: fields.containsKey('dependency_overrides'),
    ),
    _ => (member: false, overrides: false),
  };
  return switch ((package, pubspec)) {
    (.root, _) => Resolves(published),
    (.example, null) => const NotHeld(),
    (.example, String()) => switch (_outside(yaml, served, host, os)) {
      final OutsidePath outside => LeftUnresolved(outside),
      null => Resolves(published),
    },
  };
}

/// The first path dependency that leaves the package for the example whose
/// pubspec reads as [yaml], null where it is no YAML, or null where none
/// leaves or pub refuses what it reads.
OutsidePath? _outside(YamlNode? yaml, String? served, PackageName host, Os os) {
  try {
    final Map<Object?, Object?> fields = _fields(yaml);
    final PackageName self = switch (fields['name']) {
      final String name => .parse(name) ?? (throw const _Refused()),
      _ => throw const _Refused(),
    };
    final Map<PackageName, String?> overrides = switch (served) {
      null => {host: '..'},
      final String served => switch (_servedFields(served)) {
        final Map<Object?, Object?> file
            when file.containsKey('dependency_overrides') =>
          _section(file['dependency_overrides'], self),
        _ => _section(fields['dependency_overrides'], self),
      },
    };
    final List<Map<PackageName, String?>> sections = [
      _section(fields['dependencies'], self),
      _section(fields['dev_dependencies'], self),
    ];
    for (final PackageName name in {
      for (final Map<PackageName, String?> section in sections) ...section.keys,
      ...overrides.keys,
    }) {
      // pub reads a package listed in both sections by both entries, so a
      // path that leaves in either stands where no override replaces them.
      for (final String? path
          in overrides.containsKey(name)
              ? [overrides[name]]
              : [
                  for (final Map<PackageName, String?> section in sections)
                    if (section.containsKey(name)) section[name],
                ]) {
        if (path != null && _leaves(path, os)) {
          return (dependency: name, path: path);
        }
      }
    }
    return null;
  } on _Refused {
    return null;
  }
}

/// [text] read as YAML, or null where it is none.
YamlNode? _node(String text) {
  try {
    return quietYamlNode(text);
  } on YamlException {
    return null;
  }
}

/// The fields of the file read as [yaml], none where it holds no YAML, as
/// pub reads it. Throws [_Refused] where it is no YAML map.
Map<Object?, Object?> _fields(YamlNode? yaml) => switch (yaml) {
  final YamlMap map => map,
  YamlScalar(value: null) => const {},
  _ => throw const _Refused(),
};

/// The fields of served overrides whose text is [served]. Throws [_Refused]
/// where pub refuses them.
Map<Object?, Object?> _servedFields(String served) {
  final Map<Object?, Object?> fields = _fields(_node(served));
  for (final Object? key in fields.keys) {
    if (!_servedKeys.contains(key)) {
      throw const _Refused();
    }
  }
  return fields;
}

/// The fields pub reads from a `pubspec_overrides.yaml`, refusing any other.
const Set<String> _servedKeys = {
  'dependency_overrides',
  'resolution',
  'workspace',
};

/// The dependencies a section [section] of the pubspec of the package
/// [self] holds, each by its name beside its path where it is a path
/// dependency. Throws [_Refused] where pub refuses the section or an entry
/// in it.
Map<PackageName, String?> _section(Object? section, PackageName self) =>
    switch (section) {
      null => const {},
      final Map<Object?, Object?> entries => {
        for (final MapEntry<Object?, Object?>(:key, :value) in entries.entries)
          _dependencyName(key, self): _path(value),
      },
      _ => throw const _Refused(),
    };

/// The dependency [key] names in the pubspec of the package [self]. Throws
/// [_Refused] where it is no package name or [self].
PackageName _dependencyName(Object? key, PackageName self) =>
    switch (key is String ? PackageName.parse(key) : null) {
      final PackageName name when name != self => name,
      _ => throw const _Refused(),
    };

/// The path of a dependency whose spec is [spec], or null where it is by
/// another source. Throws [_Refused] where pub refuses the spec.
String? _path(Object? spec) {
  switch (spec) {
    case null:
      return null;
    case final String constraint:
      _constraint(constraint);
      return null;
    case final Map<Object?, Object?> fields:
      _constraint(fields['version']);
      return switch ([
        for (final MapEntry<Object?, Object?> entry in fields.entries)
          if (entry.key != 'version') entry,
      ]) {
        [] => null,
        [MapEntry(key: 'path', value: final String path)] => path,
        [MapEntry(key: 'path' || 'sdk', value: final Object? description)]
            when description is! String =>
          throw const _Refused(),
        [MapEntry(key: String())] => null,
        _ => throw const _Refused(),
      };
    case _:
      throw const _Refused();
  }
}

/// Throws [_Refused] where [constraint] is a version constraint pub cannot
/// read. One with no value is any version.
void _constraint(Object? constraint) {
  switch (constraint) {
    case null:
      return;
    case final String text:
      try {
        VersionConstraint.parse(text);
      } on FormatException {
        throw const _Refused();
      }
    case _:
      throw const _Refused();
  }
}

/// Whether [path], read from a package's `example/` in [os]'s paths, leaves
/// the package.
bool _leaves(String path, Os os) {
  final p.Context paths = os.paths;
  return paths.isAbsolute(path) ||
      paths.split(paths.normalize(paths.join('example', path))).first == '..';
}

/// What pub refuses in an example's pubspec or its served overrides.
final class _Refused implements Exception {
  const _Refused();
}

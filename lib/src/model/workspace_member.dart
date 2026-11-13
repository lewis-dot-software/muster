import 'package:yaml/yaml.dart';

/// Whether [pubspec], a package's `pubspec.yaml`, makes it a member of a pub
/// workspace, `resolution: workspace`. A pubspec that is no YAML map makes
/// none.
bool workspaceMember(String pubspec) {
  final Object? yaml;
  try {
    yaml = loadYaml(pubspec);
  } on YamlException {
    return false;
  }
  return yaml is YamlMap && yaml['resolution'] == 'workspace';
}

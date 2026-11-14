import 'package:yaml/yaml.dart';

import 'quiet_yaml_node.dart';

/// Whether [pubspec], a package's `pubspec.yaml`, makes it a member of a pub
/// workspace, `resolution: workspace`. A pubspec that is no YAML map makes
/// none.
bool workspaceMember(String pubspec) {
  final YamlNode yaml;
  try {
    yaml = quietYamlNode(pubspec);
  } on YamlException {
    return false;
  }
  return yaml is YamlMap && yaml['resolution'] == 'workspace';
}

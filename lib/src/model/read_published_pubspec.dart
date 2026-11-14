import 'package:yaml/yaml.dart';

import 'published_pubspec.dart';
import 'quiet_yaml_node.dart';

/// What [pubspec], an unpacked package's `pubspec.yaml`, holds. A pubspec
/// that is no YAML map holds neither.
PublishedPubspec readPublishedPubspec(String pubspec) {
  final YamlNode yaml;
  try {
    yaml = quietYamlNode(pubspec);
  } on YamlException {
    return (member: false, overrides: false);
  }
  return switch (yaml) {
    YamlMap() => (
      member: yaml['resolution'] == 'workspace',
      overrides: yaml.containsKey('dependency_overrides'),
    ),
    _ => (member: false, overrides: false),
  };
}

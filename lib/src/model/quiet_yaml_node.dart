import 'package:yaml/yaml.dart';

/// [text] read as one YAML document, as `loadYamlNode` reads it, with each
/// warning the reader gives passed over rather than written anywhere: a
/// directive it does not know, which YAML has a reader ignore, or a
/// `%YAML` of 1.3 or later, which it reads as 1.2.
///
/// Throws the [YamlException] `loadYamlNode` throws, and leaves
/// `yamlWarningCallback` as it found it either way.
YamlNode quietYamlNode(String text) {
  // The reader's warnings reach the caller through this callback alone, whose
  // default prints. The read is synchronous, so nothing else meets the
  // callback before it is put back.
  final YamlWarningCallback kept = yamlWarningCallback;
  yamlWarningCallback = (_, [_]) {};
  try {
    return loadYamlNode(text);
  } finally {
    yamlWarningCallback = kept;
  }
}

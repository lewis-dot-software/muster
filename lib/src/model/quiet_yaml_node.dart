import 'package:yaml/yaml.dart';

/// [text] read as one YAML document, as `loadYamlNode` reads it, with each
/// warning the reader gives passed over rather than written anywhere: a
/// directive it does not know, which YAML has a reader ignore, or a
/// `%YAML` of 1.3 or later, which it reads as 1.2.
///
/// Throws the [YamlException] `loadYamlNode` throws, or one for text the
/// reader refuses by a throw of another type, a tag whose `%`-escape does
/// not decode or a `%YAML` version past an integer's range, and leaves
/// `yamlWarningCallback` as it found it either way.
YamlNode quietYamlNode(String text) {
  // The reader's warnings reach the caller through this callback alone, whose
  // default prints. The read is synchronous, so nothing else meets the
  // callback before it is put back.
  final YamlWarningCallback kept = yamlWarningCallback;
  yamlWarningCallback = (_, [_]) {};
  try {
    return loadYamlNode(text);
  } on YamlException {
    rethrow;
    // The reader decodes a tag's URI by `Uri.decodeFull` and a version's
    // numbers by `int.parse`, which throw a FormatException for an escape
    // that is no UTF-8 or a number past an integer's range, and an
    // ArgumentError for an escape cut short: each a refusal of the text,
    // never a bug of muster's.
  } on FormatException catch (e) {
    throw _unreadable(e.message);
    // An index the reader reads out of range is a bug of its own, which no
    // text refuses.
    // ignore: avoid_catching_errors
  } on RangeError {
    rethrow;
    // ignore: avoid_catching_errors
  } on ArgumentError catch (e) {
    throw _unreadable('${e.message}');
  } finally {
    yamlWarningCallback = kept;
  }
}

/// The refusal of text the reader cannot read, for [reason].
YamlException _unreadable(String reason) =>
    YamlException('The text does not read: $reason.', null);

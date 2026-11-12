import 'key_path.dart';
import 'wanted.dart';
import 'written.dart';

/// Why a manifest's text refused to parse.
sealed class ManifestRefusal {
  const ManifestRefusal();
}

/// The text is not one YAML document, or its bytes are not UTF-8, which
/// YAML is read in.
final class NotYaml extends ManifestRefusal {
  /// The refusal of text that could not be read as YAML, for the [reason]
  /// given.
  const NotYaml(this.reason);

  /// What the reader said, in one line, with where it stopped: the line and
  /// column for YAML, and the byte's offset for bytes that are not UTF-8.
  final String reason;
}

/// A key muster does not know.
final class UnknownKey extends ManifestRefusal {
  /// The refusal of the key at [path].
  const UnknownKey(this.path);

  /// The unknown key's path from the top.
  final KeyPath path;
}

/// A key a codebase must hold, left out.
final class MissingKey extends ManifestRefusal {
  /// The refusal of a mapping that lacks the key at [path].
  const MissingKey(this.path);

  /// The path the missing key would stand at.
  final KeyPath path;
}

/// A value its key cannot take, or a codebase's name that is no pub package
/// name.
final class BadValue extends ManifestRefusal {
  /// The refusal of the value at [path], which must be [wanted] and is
  /// [written].
  const BadValue(this.path, this.wanted, this.written);

  /// The path of the key whose value, or whose own name, refused.
  final KeyPath path;

  /// What the value must be.
  final Wanted wanted;

  /// What the manifest writes for the value, or for the name.
  final Written written;
}

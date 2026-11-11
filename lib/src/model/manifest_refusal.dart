import 'key_path.dart';
import 'wanted.dart';

/// Why a manifest's text refused to parse.
sealed class ManifestRefusal {
  const ManifestRefusal();
}

/// The text is not one YAML document.
final class NotYaml extends ManifestRefusal {
  /// The refusal of text YAML could not read, for the [reason] it gave.
  const NotYaml(this.reason);

  /// What the YAML reader said, with the line and column it stopped at.
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
  /// The refusal of the value at [path], written [written], which must be
  /// [wanted].
  const BadValue(this.path, this.wanted, this.written);

  /// The path of the key whose value, or whose own name, refused.
  final KeyPath path;

  /// What the value must be.
  final Wanted wanted;

  /// The value's text, or the name's, as the manifest writes it.
  final String written;
}

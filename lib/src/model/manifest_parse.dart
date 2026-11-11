import 'manifest.dart';
import 'manifest_refusal.dart';

/// What parsing a manifest's text gave: its manifest, or why it refused.
sealed class ManifestParse {
  const ManifestParse();
}

/// The text is a manifest.
final class ManifestParsed extends ManifestParse {
  /// The parse that gave [manifest].
  const ManifestParsed(this.manifest);

  /// The manifest the text holds.
  final Manifest manifest;
}

/// The text refused to parse.
final class ManifestRefused extends ManifestParse {
  /// The parse that refused, for [refusal].
  const ManifestRefused(this.refusal);

  /// Why the text refused.
  final ManifestRefusal refusal;
}

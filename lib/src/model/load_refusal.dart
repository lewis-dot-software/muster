import 'codebase_name.dart';
import 'manifest_path.dart';
import 'manifest_refusal.dart';

/// Why a load refused before any fetch.
sealed class LoadRefusal {
  const LoadRefusal();
}

/// A load with no manifest: none named, no `muster.yaml` at the root, and
/// nothing in `MUSTER_MANIFESTS`.
final class NoManifest extends LoadRefusal {
  /// The refusal of a load with no manifest.
  const NoManifest();
}

/// A manifest whose file name does not end `.yaml` after a stem of its own.
final class NotManifestName extends LoadRefusal {
  /// The refusal of the manifest at [path].
  const NotManifestName(this.path);

  /// The manifest's path.
  final String path;
}

/// A manifest named that is not there.
final class ManifestMissing extends LoadRefusal {
  /// The refusal of [manifest], which is not there.
  const ManifestMissing(this.manifest);

  /// The manifest named.
  final ManifestPath manifest;
}

/// A manifest whose file could not be read.
final class ManifestUnreadable extends LoadRefusal {
  /// The refusal of [manifest], whose read failed for the [reason] the
  /// system gave.
  const ManifestUnreadable(this.manifest, this.reason);

  /// The manifest that could not be read.
  final ManifestPath manifest;

  /// What the system said.
  final String reason;
}

/// A manifest whose text refused to parse.
final class ManifestInvalid extends LoadRefusal {
  /// The refusal of [manifest], whose text refused for [refusal].
  const ManifestInvalid(this.manifest, this.refusal);

  /// The manifest whose text refused.
  final ManifestPath manifest;

  /// Why its text refused: not YAML, or a key's path in it.
  final ManifestRefusal refusal;
}

/// A codebase's name met in two of a load's manifests.
final class CodebaseNamedTwice extends LoadRefusal {
  /// The refusal of [name], met in [first] and again in [second].
  const CodebaseNamedTwice(
    this.name, {
    required this.first,
    required this.second,
  });

  /// The name met twice.
  final CodebaseName name;

  /// The manifest that names it first.
  final ManifestPath first;

  /// The manifest that names it again.
  final ManifestPath second;
}

/// A load whose working directory the system cannot give, as where it has
/// been deleted.
final class NoWorkingDirectory extends LoadRefusal {
  /// The refusal of a load whose working directory could not be read, for
  /// the [reason] the system gave.
  const NoWorkingDirectory(this.reason);

  /// What the system said.
  final String reason;
}

/// A load with no cache to clone into: none of the variables the cache's
/// directory is taken from is set.
final class NoCache extends LoadRefusal {
  /// The refusal of a load with no cache.
  const NoCache();
}

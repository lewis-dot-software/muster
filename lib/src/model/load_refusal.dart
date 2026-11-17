import 'codebase_name.dart';
import 'manifest_path.dart';
import 'manifest_refusal.dart';
import 'os.dart';
import 'refusal_text.dart';

/// Why a load refused before any fetch.
sealed class LoadRefusal {
  const LoadRefusal();

  /// This refusal in one line for a person to act on, naming its case and
  /// what it carries, any text in it holding a control character but a tab,
  /// or a line break, quoted with each escaped.
  @override
  String toString() => refusalText(this);
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
/// directory is taken from on its system is set.
final class NoCache extends LoadRefusal {
  /// The refusal of a load with no cache on [os].
  const NoCache(this.os);

  /// The system the load runs on, which sets the variables it takes the
  /// cache from.
  final Os os;
}

/// A load on a system muster takes no claim on: a POSIX system whose C
/// library it does not know, so it has no lock to hold a clone or a checkout
/// with.
final class NoClaim extends LoadRefusal {
  /// The refusal of a load on the system `dart:io` names [system].
  const NoClaim(this.system);

  /// The system's name, as `dart:io` gives it.
  final String system;
}

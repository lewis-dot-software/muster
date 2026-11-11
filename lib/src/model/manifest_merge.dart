import 'codebase_name.dart';
import 'git_codebase.dart';

/// What joining a load's manifests gave: every codebase they name, or the
/// name met twice that refuses the load.
sealed class ManifestMerge {
  const ManifestMerge();
}

/// Every codebase the manifests name, each name once.
final class Merged extends ManifestMerge {
  /// The join that gave [codebases].
  const Merged(this.codebases);

  /// The codebases in the manifests' order, each manifest's in its own.
  final List<GitCodebase> codebases;
}

/// A name met twice across the manifests.
final class NamedTwice extends ManifestMerge {
  /// The refusal of [name], met in the manifest at [first] and again in the
  /// one at [second].
  const NamedTwice(this.name, {required this.first, required this.second});

  /// The name met twice.
  final CodebaseName name;

  /// The index of the manifest that names it first.
  final int first;

  /// The index of the manifest that names it again.
  final int second;
}

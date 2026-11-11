import 'codebase_name.dart';
import 'git_codebase.dart';
import 'manifest.dart';
import 'manifest_merge.dart';
import 'named_codebase.dart';

/// Joins a load's [manifests] into every codebase they name, in their order,
/// each beside the index of the manifest that named it, or refuses on the
/// first name met twice.
ManifestMerge mergeManifests(List<Manifest> manifests) {
  final Map<CodebaseName, int> seen = {};
  final List<NamedCodebase> codebases = [];
  for (final (int index, Manifest manifest) in manifests.indexed) {
    for (final GitCodebase codebase in manifest.codebases) {
      if (seen[codebase.name] case final int first) {
        return NamedTwice(codebase.name, first: first, second: index);
      }
      seen[codebase.name] = index;
      codebases.add((codebase: codebase, manifest: index));
    }
  }
  return Merged(.unmodifiable(codebases));
}

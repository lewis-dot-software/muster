import '../model/load_refusal.dart';
import '../model/manifest_refusal.dart';
import '../model/wanted.dart';

/// Why a run refused, in a line for a person to act on.
String refusalText(LoadRefusal refusal) => switch (refusal) {
  NoManifest() =>
    'no manifest: none named, no muster.yaml in the working directory, and '
        'none in '
        'MUSTER_MANIFESTS',
  NotManifestName(:final String path) =>
    "$path: a manifest's file name ends .yaml",
  ManifestMissing(:final manifest) => '${manifest.path}: no such manifest',
  ManifestUnreadable(:final manifest, :final String reason) =>
    '${manifest.path}: $reason',
  ManifestInvalid(:final manifest, refusal: final ManifestRefusal why) =>
    '${manifest.path}: ${_manifestText(why)}',
  CodebaseNamedTwice(:final name, :final first, :final second) =>
    '${name.name}: named in ${first.path} and again in ${second.path}',
  NoWorkingDirectory(:final String reason) => 'no working directory: $reason',
  NoCache() =>
    'no cache: none of MUSTER_CACHE, XDG_CACHE_HOME, HOME or LOCALAPPDATA '
        'is set',
};

String _manifestText(ManifestRefusal refusal) => switch (refusal) {
  NotYaml(:final String reason) => 'not YAML: $reason',
  UnknownKey(:final path) => '${path.dotted}: a key muster does not know',
  MissingKey(:final path) => '${path.dotted}: missing',
  BadValue(:final path, :final Wanted wanted, :final String written) =>
    '${path.dotted}: $written is not ${_wantedText(wanted)}',
};

String _wantedText(Wanted wanted) => switch (wanted) {
  .mapping => 'a mapping',
  .packageName => 'a pub package name',
  .gitUrl => 'a git URL',
  .fullHash => "a commit's full hash",
  .toolchain => 'dart or flutter',
  .rootInsideRepo => 'a relative path inside its repo',
};

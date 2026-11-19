import 'consumer_root.dart';
import 'load_refusal.dart';
import 'on_one_line.dart';
import 'os.dart';

/// Why a load refused, in one line for a person to act on, any text in it
/// holding a control character but a tab, or a line break, quoted with each
/// escaped.
String refusalText(LoadRefusal refusal) => switch (refusal) {
  NoManifest(:final ConsumerRoot root) =>
    'no manifest: none named, no muster.yaml at ${onOneLine(root.path)}, and '
        'none '
        'in MUSTER_MANIFESTS',
  NotManifestName(:final String path) =>
    "${onOneLine(path)}: a manifest's file name ends .yaml",
  ManifestMissing(:final manifest) =>
    '${onOneLine(manifest.path)}: no such manifest',
  ManifestUnreadable(:final manifest, :final String reason) =>
    '${onOneLine(manifest.path)}: ${onOneLine(reason)}',
  ManifestInvalid(:final manifest, :final refusal) =>
    '${onOneLine(manifest.path)}: $refusal',
  CodebaseNamedTwice(:final name, :final first, :final second) =>
    '${name.name}: named in ${onOneLine(first.path)} and again in '
        '${onOneLine(second.path)}',
  NoWorkingDirectory(:final String reason) =>
    'no working directory: ${onOneLine(reason)}',
  NoCache(:final Os os) => 'no cache: ${_cacheText(os)}',
  NoClaim(:final String system) =>
    'no claim: muster knows no C library to lock a claim with on '
        '${onOneLine(system)}',
};

/// The variables [os] takes the cache from, none of them set.
String _cacheText(Os os) => switch (os) {
  .posix =>
    'none of MUSTER_CACHE, XDG_CACHE_HOME as an absolute path, or HOME is '
        'set',
  .windows => 'neither MUSTER_CACHE nor LOCALAPPDATA is set',
};

import 'dart:io';
import 'dart:isolate';

import 'package:muster/muster.dart';
import 'package:muster/src/load/loader.dart';
import 'package:muster/src/model/cache_directory.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/clone_path.dart';
import 'package:muster/src/model/environment.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'git.dart';
import 'manifests.dart';
import 'packages.dart';

/// The environment a test's load reads, in [temp]: [hermetic]'s, less any
/// `MUSTER_MANIFESTS` it carries, its cache in [temp], and [variables] over
/// the rest.
Environment loadEnvironment(
  Directory temp, [
  Map<String, String> variables = const {},
]) => (
  variables: {
    ...hermetic(temp)..remove('MUSTER_MANIFESTS'),
    'MUSTER_CACHE': p.join(temp.path, 'cache'),
    ...variables,
  },
  os: .posix,
);

/// The variables a cache's directory can be taken from.
const Set<String> _cacheVariables = {
  'MUSTER_CACHE',
  'XDG_CACHE_HOME',
  'HOME',
  'LOCALAPPDATA',
};

/// The cache a test's load in [temp] clones into.
CacheDirectory loadCacheIn(Directory temp) => .of(loadEnvironment(temp))!;

/// The clone of [codebase]'s URL in the cache of a test's load in [temp].
ClonePath cloneOf(Directory temp, GitCodebase codebase) =>
    .of(loadCacheIn(temp), codebase.url);

/// A loader in [temp], reading [loadEnvironment] with [variables], and with
/// none of the variables a cache is taken from where [cached] does not hold,
/// its working directory the consumer's root, its processes run by [runner].
Loader loaderIn(
  Directory temp,
  Runner runner, {
  Map<String, String> variables = const {},
  bool cached = true,
}) => .new(
  (
    variables: {
      for (final MapEntry<String, String>(:key, :value) in loadEnvironment(
        temp,
        variables,
      ).variables.entries)
        if (cached || !_cacheVariables.contains(key)) key: value,
    },
    os: .posix,
  ),
  .new(consumerIn(temp).path, .posix),
  runner,
);

/// A runner in [temp] that can start no process, since its `PATH` holds no
/// executable.
Runner unstartableIn(Directory temp) =>
    .new({...hermetic(temp), 'PATH': '/muster-no-such-directory'});

/// The directory of muster's own package, read from its package config.
Future<String> musterRoot() async => p.dirname(
  p.dirname(
    (await Isolate.resolvePackageUri(.parse('package:muster/muster.dart')))!
        .toFilePath(),
  ),
);

/// The checkout of the codebase [name] under the consumer's root in [temp].
String checkoutAt(Directory temp, String name) =>
    CheckoutPath.of(consumerIn(temp), .parse(name)!).path;

/// The path of the manifest [name] at the consumer's root in [temp].
String atRoot(Directory temp, [String name = 'muster.yaml']) =>
    p.join(consumerIn(temp).path, name);

/// Writes the manifest naming [codebases] at [path], its directory made.
Future<void> writeManifest(String path, List<GitCodebase> codebases) async {
  final File file = await File(path).create(recursive: true);
  await file.writeAsString(renderManifest(codebases.map(entryOf).toList()));
}

/// The kept locks beside the manifest at [path].
LocksDirectory locksBeside(String path) => .beside(.parse(path, .posix)!);

/// Matches a load refused for [reason].
Matcher refusedFor(Matcher reason) =>
    isA<Refused>().having((Refused r) => r.reason, 'reason', reason);

/// Matches a load that gave an outcome to each name of [outcomes] alone,
/// in its order, each matching its matcher.
Matcher loadedWith(Map<String, Matcher> outcomes) {
  TypeMatcher<Loaded> loaded = isA<Loaded>().having(
    (Loaded l) => [for (final CodebaseName name in l.outcomes.keys) name.name],
    'names',
    outcomes.keys.toList(),
  );
  for (final MapEntry<String, Matcher>(:key, :value) in outcomes.entries) {
    loaded = loaded.having(
      (Loaded l) => l.outcomes[CodebaseName.parse(key)!],
      key,
      value,
    );
  }
  return loaded;
}

/// Matches an outcome of [Fetched] whose package is at [path].
Matcher fetchedAt(String path) =>
    isA<Fetched>().having((Fetched f) => f.package.path, 'package', path);

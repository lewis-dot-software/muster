import 'dart:convert';
import 'dart:io';

import 'package:muster/src/model/checkout.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/package_path.dart';
import 'package:muster/src/model/resolution.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:muster/src/store/checkouts.dart';
import 'package:path/path.dart' as p;

import 'manifests.dart';
import 'package_server.dart';

/// The variables that send a test's pub to [server], its cache in [temp], so
/// no archive it serves reaches the user's own cache.
Map<String, String> pubVariables(Directory temp, PackageServer server) => {
  'PUB_HOSTED_URL': server.url,
  'PUB_CACHE': p.join(temp.path, 'pub-cache'),
};

/// The pubspec of the package [name] at [version], depending on each of
/// [dependencies] and dev depending on each of [devDependencies] from the
/// host it is served from, each beside its constraint, and a member of a pub
/// workspace where [workspace] holds.
String hostedPubspec(
  String name,
  String version, {
  Map<String, String> dependencies = const {},
  Map<String, String> devDependencies = const {},
  bool workspace = false,
}) => [
  'name: $name',
  'version: $version',
  'environment:',
  // A workspace's members need a language version that knows workspaces.
  '  sdk: ^3.${workspace ? 6 : 0}.0',
  if (workspace) 'resolution: workspace',
  if (dependencies.isNotEmpty) 'dependencies:',
  for (final MapEntry<String, String>(:key, :value) in dependencies.entries)
    '  $key: ${jsonEncode(value)}',
  if (devDependencies.isNotEmpty) 'dev_dependencies:',
  for (final MapEntry<String, String>(:key, :value) in devDependencies.entries)
    '  $key: ${jsonEncode(value)}',
  '',
].join('\n');

/// The pubspec of the example of the package [name], depending on it by its
/// path, and a member of a pub workspace where [workspace] holds.
String examplePubspec(String name, {bool workspace = false}) =>
    'name: ${name}_example\n'
    'environment:\n'
    '  sdk: ^3.${workspace ? 6 : 0}.0\n'
    '${workspace ? 'resolution: workspace\n' : ''}'
    'dependencies:\n'
    '  $name:\n'
    '    path: ..\n';

/// [codebase]'s kept locks written by [checkouts] in [locks], then its
/// checkout made on them.
Future<Checkout> lockedCheckout(
  Checkouts checkouts,
  LocksDirectory locks,
  HostedCodebase codebase,
) async {
  await checkouts.lock(Hosted(codebase), locks);
  return checkouts.checkout(Hosted(codebase), locks);
}

/// Serves the package [name] at [version] on [server], with no dependency,
/// its example where [example] holds, and each of [files] beside them.
void serveLeaf(
  PackageServer server,
  String name,
  String version, {
  bool example = false,
  Map<String, String> files = const {},
}) => server.serve(name, version, {
  'pubspec.yaml': hostedPubspec(name, version),
  if (example) 'example/pubspec.yaml': examplePubspec(name),
  ...files,
});

/// The hosted codebase `app`, fetching the package [package] at [version],
/// resolved by [resolution] with `dart`.
HostedCodebase hostedOf(
  String package, {
  String name = 'app',
  String version = '1.0.0',
  Resolution resolution = .alone,
  Toolchain toolchain = .dart,
}) => hosted(name, package, version, resolution, toolchain);

/// A `pubspec.lock` pinning the package [name] at [version] from [server],
/// as a package may be served with.
String servedLock(String name, String version, PackageServer server) =>
    'packages:\n'
    '  $name:\n'
    '    dependency: "direct main"\n'
    '    description:\n'
    '      name: $name\n'
    '      url: "${server.url}"\n'
    '    source: hosted\n'
    '    version: "$version"\n'
    'sdks:\n'
    '  dart: ">=3.0.0 <4.0.0"\n';

/// The names of the packages the `package_config.json` of [package] lists.
Future<Set<String>> configuredIn(PackagePath package) async {
  final Map<String, Object?> config = jsonDecode(
    await File(package.packageConfig.path).readAsString(),
  ) as Map<String, Object?>;
  return {
    for (final Object? entry in config['packages']! as List<Object?>)
      (entry! as Map<String, Object?>)['name']! as String,
  };
}

/// What a hosted checkout at [checkout] of [codebase] holds beside the files
/// pub serves: each resolve's lock and `.dart_tool/` in each of [packages],
/// from the checkout's top in `/` separators.
List<String> resolvedIn(
  CheckoutPath checkout,
  HostedCodebase codebase,
  Set<Package> packages,
) => [
  for (final Package package in packages)
    for (final String written in ['pubspec.lock', '.dart_tool'])
      p.posix.normalize(
        p.posix.joinAll([
          ...p.split(
            p.relative(
              hostedPackage(checkout, codebase, package).path,
              from: checkout.path,
            ),
          ),
          written,
        ]),
      ),
];

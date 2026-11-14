import 'dart:convert';

import 'codebase.dart';
import 'codebase_name.dart';
import 'commit.dart';
import 'content_hash.dart';
import 'git_url.dart';
import 'lock_source.dart';
import 'outside_path.dart';
import 'package.dart';
import 'package_name.dart';
import 'package_version.dart';
import 'repo_root.dart';
import 'resolution.dart';
import 'sdk_version.dart';
import 'stamp.dart';
import 'stamped_package.dart';
import 'toolchain.dart';

/// The stamp [text] holds, a JSON object of a stamp's values, or null where it
/// holds none: text that is no JSON object of exactly the keys of a stamp of
/// one kind, a value its key cannot take, packages that leave out the
/// root, or an unresolved example beside a stamped one.
Stamp? parseStamp(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json
      case {
        'sdk': final String sdk,
        'packages': final Map<String, Object?> packages,
        'unresolved': final Object? unresolved,
      }
      when json.length == _stampKeys) {
    final Map<Package, StampedPackage>? stamped = _packages(packages);
    if ((_codebase(json), SdkVersion.parse(sdk), _unresolved(unresolved))
        case (
          final Codebase codebase,
          final SdkVersion sdk,
          (final OutsidePath? outside,),
        )
        when stamped != null &&
            stamped.containsKey(Package.root) &&
            (outside == null || !stamped.containsKey(Package.example))) {
      return (
        codebase: codebase,
        packages: stamped,
        unresolved: outside,
        sdk: sdk,
      );
    }
  }
  return null;
}

/// How many keys a stamp's object holds, of either kind.
const int _stampKeys = 8;

/// The unresolved example's path dependency a stamp's [json] names, null
/// within the record where it names none, or null where [json] is neither
/// null nor an object of exactly its two keys holding a package's name.
(OutsidePath?,)? _unresolved(Object? json) => switch (json) {
  null => (null,),
  {'dependency': final String dependency, 'path': final String path}
      when json.length == 2 =>
    switch (PackageName.parse(dependency)) {
      final PackageName dependency => ((dependency: dependency, path: path),),
      null => null,
    },
  _ => null,
};

/// How many keys a stamped package's object holds.
const int _packageKeys = 3;

final Map<String, Package> _packageNames = Package.values.asNameMap();
final Map<String, LockSource> _sources = LockSource.values.asNameMap();

/// The codebase a stamp's object [json] names, by the keys of its kind, or
/// null where it names none.
Codebase? _codebase(Map<Object?, Object?> json) => switch (json) {
  {
    'name': final String name,
    'git': final String git,
    'commit': final String commit,
    'root': final String root,
    'toolchain': final String toolchain,
  } =>
    switch ((
      CodebaseName.parse(name),
      GitUrl.parse(git),
      Commit.parse(commit),
      RepoRoot.parse(root),
      Toolchain.parse(toolchain),
    )) {
      (
        final CodebaseName name,
        final GitUrl url,
        final Commit commit,
        final RepoRoot root,
        final Toolchain toolchain,
      ) =>
        Git((
          name: name,
          url: url,
          commit: commit,
          root: root,
          toolchain: toolchain,
        )),
      _ => null,
    },
  {
    'name': final String name,
    'hosted': final String package,
    'version': final String version,
    'resolution': final String resolution,
    'toolchain': final String toolchain,
  } =>
    switch ((
      CodebaseName.parse(name),
      PackageName.parse(package),
      PackageVersion.parse(version),
      Resolution.parse(resolution),
      Toolchain.parse(toolchain),
    )) {
      (
        final CodebaseName name,
        final PackageName package,
        final PackageVersion version,
        final Resolution resolution,
        final Toolchain toolchain,
      ) =>
        Hosted((
          name: name,
          package: package,
          version: version,
          resolution: resolution,
          toolchain: toolchain,
        )),
      _ => null,
    },
  _ => null,
};

Map<Package, StampedPackage>? _packages(Map<String, Object?> json) {
  final Map<Package, StampedPackage> packages = {};
  for (final MapEntry<String, Object?>(:key, :value) in json.entries) {
    final Package? package = _packageNames[key];
    if (package == null) {
      return null;
    }
    if (value
        case {
          'source': final String source,
          'lock': final String lock,
          'packageConfig': final String packageConfig,
        }
        when value.length == _packageKeys) {
      if ((
            _sources[source],
            ContentHash.parse(lock),
            ContentHash.parse(packageConfig),
          )
          case (
            final LockSource source,
            final ContentHash lock,
            final ContentHash packageConfig,
          )) {
        packages[package] = (
          source: source,
          lock: lock,
          packageConfig: packageConfig,
        );
        continue;
      }
    }
    return null;
  }
  return packages;
}

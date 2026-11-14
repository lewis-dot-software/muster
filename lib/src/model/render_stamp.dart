import 'dart:convert';

import 'codebase.dart';
import 'git_codebase.dart';
import 'hosted_codebase.dart';
import 'package.dart';
import 'package_name.dart';
import 'stamp.dart';
import 'stamped_package.dart';

/// The text of [stamp], a JSON object of its values, its codebase's as its
/// kind writes them, its packages in [Package]'s order and its unresolved
/// example's path dependency, null where there is none.
String renderStamp(Stamp stamp) {
  final Map<String, Object?> codebase = switch (stamp.codebase) {
    Git(codebase: final GitCodebase git) => {
      'name': git.name.name,
      'git': git.url.url,
      'commit': git.commit.hash,
      'root': git.root.path,
      'toolchain': git.toolchain.name,
    },
    Hosted(codebase: final HostedCodebase hosted) => {
      'name': hosted.name.name,
      'hosted': hosted.package.name,
      'version': hosted.version.version,
      'resolution': hosted.resolution.word,
      'toolchain': hosted.toolchain.name,
    },
  };
  final Map<String, Object?> packages = {
    for (final Package package in Package.values)
      if (stamp.packages[package] case final StampedPackage stamped)
        package.name: {
          'source': stamped.source.name,
          'lock': stamped.lock.hex,
          'packageConfig': stamped.packageConfig.hex,
        },
  };
  final String json = const JsonEncoder.withIndent('  ').convert({
    ...codebase,
    'sdk': stamp.sdk.version,
    'packages': packages,
    'unresolved': switch (stamp.unresolved) {
      (:final PackageName dependency, :final String path) => {
        'dependency': dependency.name,
        'path': path,
      },
      null => null,
    },
  });
  return '$json\n';
}

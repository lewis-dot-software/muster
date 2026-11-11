import 'dart:convert';

import 'package.dart';
import 'stamp.dart';
import 'stamped_package.dart';

/// The text of [stamp], a JSON object of its values, its packages in
/// [Package]'s order.
String renderStamp(Stamp stamp) {
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
    'git': stamp.url.url,
    'commit': stamp.commit.hash,
    'root': stamp.root.path,
    'toolchain': stamp.toolchain.name,
    'sdk': stamp.sdk.version,
    'packages': packages,
  });
  return '$json\n';
}

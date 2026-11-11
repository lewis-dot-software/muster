import 'consumer_root.dart';
import 'environment.dart';
import 'manifest_sought.dart';
import 'os.dart';
import 'working_directory.dart';

/// The manifests a load looks for, in the order it reads them, each path
/// made absolute against [workingDirectory]: the [named] ones alone where
/// any is given, and else the `muster.yaml` at [root] followed by every path
/// `MUSTER_MANIFESTS` lists in [environment], split on the system's path
/// list separator, an empty entry passed over.
List<ManifestSought> seekManifests(
  List<String> named,
  Environment environment,
  ConsumerRoot root,
  WorkingDirectory workingDirectory,
) {
  final Os os = environment.os;
  ManifestSought sought(String path, {required bool named}) =>
      (path: workingDirectory.resolve(path), named: named);
  if (named.isNotEmpty) {
    return [for (final String path in named) sought(path, named: true)];
  }
  return [
    sought(os.paths.join(root.path, 'muster.yaml'), named: false),
    for (final String path
        in (environment.variables['MUSTER_MANIFESTS'] ?? '').split(
          os.pathListSeparator,
        ))
      if (path.isNotEmpty) sought(path, named: true),
  ];
}

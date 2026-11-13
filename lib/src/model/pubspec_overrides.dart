import 'hosted_codebase.dart';
import 'package.dart';

/// The `pubspec_overrides.yaml` for [codebase]'s [package], or null where it
/// takes none: none where [holding], the package holding one already, and
/// otherwise by [member], whether its pubspec makes it a member of a pub
/// workspace.
///
/// A workspace member's sets no resolution. The example's overrides the
/// package to its own path. The root resolved as a dependency takes none.
String? pubspecOverrides(
  HostedCodebase codebase,
  Package package, {
  required bool member,
  required bool holding,
}) {
  if (holding) {
    return null;
  }
  final String resolution = member ? 'resolution:\n' : '';
  return switch ((package, codebase.resolution)) {
    (.root, .alone) => member ? resolution : null,
    (.root, .asDependency) => null,
    (.example, _) =>
      '$resolution'
          'dependency_overrides:\n'
          '  ${codebase.package.name}:\n'
          '    path: ..\n',
  };
}

import 'hosted_codebase.dart';
import 'package.dart';
import 'published_pubspec.dart';

/// The `pubspec_overrides.yaml` for [codebase]'s [package], or null where it
/// takes none: none where [holding], the package holding one already, and
/// otherwise by what its [published] pubspec holds.
///
/// A workspace member's sets no resolution. The root resolved alone sets no
/// dependency overrides where its pubspec holds some, so it resolves as a
/// consumer's dependency on it would. The example's overrides the package
/// to its own path. The root resolved as a dependency takes none.
String? pubspecOverrides(
  HostedCodebase codebase,
  Package package, {
  required PublishedPubspec published,
  required bool holding,
}) {
  if (holding) {
    return null;
  }
  final String resolution = published.member ? 'resolution:\n' : '';
  return switch ((package, codebase.resolution)) {
    (.root, .alone) => switch ('$resolution'
        '${published.overrides ? 'dependency_overrides:\n' : ''}') {
      '' => null,
      final String overrides => overrides,
    },
    (.root, .asDependency) => null,
    (.example, _) =>
      '$resolution'
          'dependency_overrides:\n'
          '  ${codebase.package.name}:\n'
          '    path: ..\n',
  };
}

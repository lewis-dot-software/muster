import 'command.dart';
import 'executable.dart';
import 'package_path.dart';

/// The toolchain that resolves a codebase.
enum Toolchain {
  /// The Dart SDK's `dart`.
  dart,

  /// The Flutter SDK's `flutter`.
  flutter;

  /// The executable the toolchain runs.
  Executable get executable => switch (this) {
    .dart => .dart,
    .flutter => .flutter,
  };

  /// The command that writes the version of the toolchain's SDK.
  Command get version => (
    executable: executable,
    arguments: switch (this) {
      .dart => ['--version'],
      .flutter => ['--version', '--machine'],
    },
  );

  /// The command that resolves [package] alone on the `pubspec.lock` it
  /// holds, failing where the lock does not hold, and leaving any `example/`
  /// in it unresolved.
  Command resolve(PackagePath package) => (
    executable: executable,
    arguments: [
      'pub',
      'get',
      '--enforce-lockfile',
      '--no-example',
      '--directory=${package.path}',
    ],
  );
}

import 'package:path/path.dart' as p;

/// The family of operating system muster runs on, which sets how its paths
/// are written and where its cache sits.
enum Os {
  /// Linux, macOS and every other system with `/` paths.
  posix,

  /// Windows.
  windows;

  /// The path style the system writes its paths in.
  p.Context get paths => switch (this) {
    .posix => p.posix,
    .windows => p.windows,
  };

  /// The character a list of paths in one variable is split on, as `PATH`
  /// is: `:`, and `;` on Windows, whose paths hold `:`.
  String get pathListSeparator => switch (this) {
    .posix => ':',
    .windows => ';',
  };
}

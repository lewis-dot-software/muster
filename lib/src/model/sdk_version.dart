import 'dart:convert';

import 'toolchain.dart';

/// The version of the SDK a toolchain on `PATH` runs, as it names it: the
/// Dart SDK's for `dart`, and the Flutter framework's for `flutter`.
extension type const SdkVersion._(String version) {
  /// The version [text] is, or null where it is empty or holds whitespace.
  static SdkVersion? parse(String text) =>
      text.isEmpty || text.contains(_whitespace) ? null : ._(text);
}

/// The version [toolchain]'s version command wrote in [output], or null where
/// the output names none: the word after `Dart SDK version:` for
/// `dart --version`, and `frameworkVersion` in the JSON object
/// `flutter --version --machine` writes, past any line before it.
SdkVersion? readSdkVersion(Toolchain toolchain, String output) =>
    switch (toolchain) {
      .dart => switch (_dartVersion.firstMatch(output)?.group(1)) {
        final String version => .parse(version),
        null => null,
      },
      .flutter => _frameworkVersion(output),
    };

final RegExp _whitespace = .new(r'\s');

final RegExp _dartVersion = .new(r'Dart SDK version: (\S+)');

SdkVersion? _frameworkVersion(String output) {
  final int start = output.indexOf('{');
  final int end = output.lastIndexOf('}');
  if (start < 0 || end < start) {
    return null;
  }
  final Object? json;
  try {
    json = jsonDecode(output.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  return switch (json) {
    {'frameworkVersion': final String version} => .parse(version),
    _ => null,
  };
}

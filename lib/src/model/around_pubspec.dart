import 'dart:convert';

import 'hosted_codebase.dart';

/// The name of the package muster writes around a hosted package resolved
/// as a dependency.
const String aroundName = 'muster_around';

/// The `pubspec.yaml` of the package around [codebase]'s, in the checkout's
/// top: [aroundName], depending on the unpacked package by its path, and
/// overriding it to that path, so a dependency of its own that depends back
/// on it from its host resolves to it too.
String aroundPubspec(HostedCodebase codebase) {
  final String package = codebase.package.name;
  final String path = jsonEncode('$package-${codebase.version.version}');
  return 'name: $aroundName\n'
      'publish_to: none\n'
      'environment:\n'
      '  sdk: ^3.0.0\n'
      'dependencies:\n'
      '  $package:\n'
      '    path: $path\n'
      'dependency_overrides:\n'
      '  $package:\n'
      '    path: $path\n';
}

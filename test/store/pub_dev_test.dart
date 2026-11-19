import 'dart:io';

import 'package:muster/src/model/checkout.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/package_path.dart';
import 'package:muster/src/store/checkouts.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/git.dart';
import '../support/host.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/packages.dart';

/// Every host the `pubspec.lock` [package]'s resolve wrote names a hosted
/// package from.
Future<Set<String>> _hostsIn(PackagePath package) async {
  final YamlMap lock =
      loadYaml(await File(package.lock.path).readAsString()) as YamlMap;
  return {
    for (final Object? locked in (lock['packages'] as YamlMap).values)
      if (locked case {
        'source': 'hosted',
        'description': {'url': final String url},
      })
        url,
  };
}

/// The version of Flutter that `flutter pub get` writes beside the
/// `package_config.json` of [package]'s resolve, or null where no Flutter
/// resolve wrote one.
Future<String?> _flutterVersionIn(PackagePath package) async {
  final File version = .new(
    p.join(p.dirname(package.packageConfig.path), 'version'),
  );
  return await version.exists() ? version.readAsString() : null;
}

/// A hosted package fetched from pub.dev itself, one test per toolchain, its
/// archives in the user's own pub cache.
void main() {
  late Directory temp;
  late Checkouts checkouts;
  late LocksDirectory locks;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    final Runner runner = .new(hermetic(temp)..remove('PUB_HOSTED_URL'), host);
    checkouts = checkoutsIn(temp, runner);
    locks = locksBeside(atRoot(temp));
  });

  tearDown(() => temp.delete(recursive: true));

  test('dio, whose dio_web_adapter depends back on it, resolves with dart '
      'as a dependency, against pub.dev', () async {
    final HostedCodebase dio = hostedOf(
      'dio',
      name: 'dio',
      version: '5.9.0',
      resolution: .asDependency,
    );
    final Checkout checkout = await lockedCheckout(checkouts, locks, dio);
    expect(checkout.package.path, endsWith('/dio-5.9.0'));
    expect(
      await configuredIn(checkout.package),
      containsAll(['dio', 'dio_web_adapter']),
    );
    expect(await _hostsIn(checkout.package), {'https://pub.dev'});
    expect(await _flutterVersionIn(checkout.package), isNull);
  });

  test('path resolves with flutter alone, against pub.dev, its dev '
      'dependencies among its packages', () async {
    final HostedCodebase path = hostedOf(
      'path',
      name: 'path',
      version: '1.9.1',
      toolchain: .flutter,
    );
    final Checkout checkout = await lockedCheckout(checkouts, locks, path);
    expect(await configuredIn(checkout.package), containsAll(['path', 'test']));
    expect(await _hostsIn(checkout.package), {'https://pub.dev'});
    expect(await _flutterVersionIn(checkout.package), checkout.sdk);
  });
}

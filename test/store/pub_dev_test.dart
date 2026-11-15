import 'dart:io';

import 'package:muster/src/model/checkout.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/store/checkouts.dart';
import 'package:muster/src/store/runner.dart';
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/packages.dart';

/// A hosted package fetched from pub.dev itself, one test per toolchain, its
/// archives in the user's own pub cache.
void main() {
  late Directory temp;
  late Checkouts checkouts;
  late LocksDirectory locks;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    final Runner runner = .new(hermetic(temp)..remove('PUB_HOSTED_URL'));
    checkouts = checkoutsIn(temp, runner);
    locks = locksBeside(atRoot(temp));
  });

  tearDown(() => temp.delete(recursive: true));

  test('dio, whose dio_web_adapter depends back on it, resolves with dart '
      'as a dependency', () async {
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
  });

  test('path resolves with flutter alone, its dev dependencies among its '
      'packages', () async {
    final HostedCodebase path = hostedOf(
      'path',
      name: 'path',
      version: '1.9.1',
      toolchain: .flutter,
    );
    final Checkout checkout = await lockedCheckout(checkouts, locks, path);
    expect(await configuredIn(checkout.package), containsAll(['path', 'test']));
  });
}

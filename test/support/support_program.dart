import 'dart:io';

import 'package:path/path.dart' as p;

import 'kernel_cache.dart';
import 'loads.dart';
import 'locker.dart';

/// A program of muster's test support a test starts apart from itself, from
/// the kernel kept of it.
enum SupportProgram {
  /// The contender, `contender_main.dart`.
  contender('contender_main.dart'),

  /// The gone probe, `gone_probe.dart`.
  gone('gone_probe.dart');

  const SupportProgram(this.main);

  /// The program's file, under `test/support`.
  final String main;

  /// The path of the program's kernel, compiled where its sources have
  /// changed since the kernel kept.
  Future<String> kernel() async => (await cache()).kernel();

  /// The arguments that start the program's kernel, in a process of its own
  /// on the VM running the test, with [arguments] after it.
  Future<List<String>> started(List<String> arguments) async => [
    '--packages=${packagesOf(await musterRoot())}',
    await kernel(),
    ...arguments,
  ];

  /// The cache of the program's kernel, compiled by the SDK running the test
  /// from muster's own code, the test support and the packages they resolve
  /// through, and kept beside muster's own checkouts as
  /// `<name>-<key>.dill`.
  Future<KernelCache> cache() async {
    final String root = await musterRoot();
    return .new(
      checkout: .of(.new(root, .posix), .parse(name)!),
      sources: [
        p.join(root, 'lib'),
        p.join(root, 'test', 'support'),
        packagesOf(root),
      ],
      sdk: Platform.version,
      compile: (String output) => compile(root, output),
      claims: .new(testLocker),
    );
  }

  /// Compiles the program of muster's own package at [root] into the kernel
  /// at [output] by the SDK running the test, writing every file it is
  /// compiled from to [depfile] where one is given.
  ///
  /// Throws a [StateError] where the compile fails.
  Future<void> compile(String root, String output, [String? depfile]) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      [
        'compile',
        'kernel',
        '--packages=${packagesOf(root)}',
        '--output=$output',
        if (depfile != null) '--depfile=$depfile',
        p.join(root, 'test', 'support', main),
      ],
    );
    if (result.exitCode != 0) {
      throw StateError('the $name program did not compile: ${result.stderr}');
    }
  }
}

/// The package config of muster's own package at [root].
String packagesOf(String root) =>
    p.join(root, '.dart_tool', 'package_config.json');

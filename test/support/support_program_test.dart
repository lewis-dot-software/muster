import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'kernel_cache.dart';
import 'loads.dart';
import 'support_program.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
  });

  tearDown(() => temp.delete(recursive: true));

  for (final SupportProgram program in SupportProgram.values) {
    test("The ${program.name} program's kernel is keyed by the SDK running "
        'the test and by every file a compile of it reads', () async {
      final String root = await musterRoot();
      final KernelCache cache = await program.cache();
      final String depfile = p.join(temp.path, '${program.name}.d');
      await program.compile(
        root,
        p.join(temp.path, '${program.name}.dill'),
        depfile,
      );
      final List<String> hosted = cache.sources.contains(packagesOf(root))
          ? await _hostedRoots(packagesOf(root))
          : const [];
      bool keyed(String file) =>
          cache.sources.any(
            (String source) => file == source || p.isWithin(source, file),
          ) ||
          hosted.any((String package) => p.isWithin(package, file));
      expect(cache.sdk, Platform.version);
      expect([
        for (final String file in await _dependencies(depfile))
          if (!keyed(file)) file,
      ], isEmpty);
    });
  }
}

/// Every file the depfile at [depfile] names a compile's output as reading.
Future<List<String>> _dependencies(String depfile) async {
  final String text = await File(depfile).readAsString();
  return [
    for (final String file
        in text.substring(text.indexOf(': ') + 2).trim().split(_unescaped))
      file.replaceAll(r'\ ', ' '),
  ];
}

/// A space a depfile separates its files by, never one it escapes.
final RegExp _unescaped = .new(r'(?<!\\) +');

/// The root of each hosted package the package config at [config] names,
/// whose files the version it names fixes.
Future<List<String>> _hostedRoots(String config) async => [
  for (final Object? package
      in (jsonDecode(await File(config).readAsString())
              as Map<String, Object?>)['packages']!
          as List<Object?>)
    if (Uri.file(config)
            .resolve((package! as Map<String, Object?>)['rootUri']! as String)
            .toFilePath()
        case final String root when p.split(root).contains('hosted'))
      root,
];

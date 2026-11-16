import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

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
      final List<String> pinned = cache.sources.contains(packagesOf(root))
          ? await _pinnedRoots(packagesOf(root), p.join(root, 'pubspec.lock'))
          : const [];
      bool keyed(String file) =>
          cache.sources.any(
            (String source) => file == source || p.isWithin(source, file),
          ) ||
          pinned.any((String package) => p.isWithin(package, file));
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

/// The root, by the package config at [config], of each package the lock
/// at [lock] names from pub.dev or a git repo, whose files the version or
/// the commit the lock names fixes.
Future<List<String>> _pinnedRoots(String config, String lock) async {
  final YamlMap locked =
      (loadYaml(await File(lock).readAsString()) as YamlMap)['packages']
          as YamlMap;
  final Set<String> pinned = {
    for (final MapEntry<Object?, Object?>(:key, :value) in locked.entries)
      if ((value! as YamlMap)['source'] case 'hosted' || 'git') key! as String,
  };
  return [
    for (final Object? package
        in (jsonDecode(await File(config).readAsString())
                as Map<String, Object?>)['packages']!
            as List<Object?>)
      if (package! as Map<String, Object?>
          case {'name': final String name, 'rootUri': final String rootUri}
          when pinned.contains(name))
        Uri.file(config).resolve(rootUri).toFilePath(),
  ];
}

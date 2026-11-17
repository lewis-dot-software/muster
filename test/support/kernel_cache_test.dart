import 'dart:io';
import 'dart:isolate';

import 'package:grit/grit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'git.dart';
import 'kernel_cache.dart';
import 'locker.dart';
import 'packages.dart';
import 'write_file.dart';

/// A kernel cache in [temp] over a source directory and a source file, its
/// compiles counted in a file, so an isolate's count as much as the test's.
final class _Bench {
  _Bench(this.temp);

  final Directory temp;

  /// Whether the next compile throws.
  bool failing = false;

  /// The file each compile writes a line to.
  File get _log => .new(p.join(temp.path, 'compiles'));

  /// How many kernels have been compiled so far.
  Future<int> compiles() async =>
      await _log.exists() ? (await _log.readAsLines()).length : 0;

  String get directory => p.join(temp.path, 'sources');

  String get file => p.join(temp.path, 'packages.json');

  KernelCache cache([String sdk = '3.13.7']) => .new(
    checkout: .of(consumerIn(temp), .parse('contender')!),
    sources: [directory, file],
    sdk: sdk,
    compile: (String output) async {
      await _log.writeAsString('$output\n', mode: .append, flush: true);
      await File(output).writeAsString('kernel ${await compiles()}');
      if (failing) {
        throw StateError('the compile failed');
      }
    },
    claims: .new(testLocker),
  );

  /// The names of the files beside the kernel.
  Future<Set<String>> kept() async => {
    await for (final FileSystemEntity entity in Directory(
      p.join(consumerIn(temp).path, '.dart_tool', 'muster'),
    ).list())
      p.basename(entity.path),
  };
}

/// What a draw does to the sources, or asks of the cache.
enum _Step {
  /// Asks for the kernel.
  ask,

  /// Rewrites the source directory's file's contents.
  edit,

  /// Rewrites the source file's contents.
  rewrite,

  /// Rewrites the source directory's file's contents back to their first.
  restore,

  /// Adds a file to the source directory.
  add,
}

void main() {
  late Directory temp;
  late _Bench bench;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    bench = .new(temp);
    await writeFile(p.join(bench.directory, 'a.dart'), 'first');
    await writeFile(bench.file, 'packages');
  });

  tearDown(() => temp.delete(recursive: true));

  test('A kernel asked for twice from unchanged sources is compiled once, '
      'and both asks name it', () async {
    final String first = await bench.cache().kernel();
    final String second = await bench.cache().kernel();
    expect(second, first);
    expect(await bench.compiles(), 1);
    expect(await File(first).readAsString(), 'kernel 1');
  });

  test(
    'Kernels asked for at once from separate isolates are compiled once',
    () async {
      final _Bench shared = bench;
      final List<String> kernels = await Future.wait([
        for (int i = 0; i < 5; i++) Isolate.run(() => shared.cache().kernel()),
      ]);
      expect(kernels.toSet(), hasLength(1));
      expect(await bench.compiles(), 1);
    },
  );

  for (final (String change, Future<void> Function() changed) in [
    (
      "a source directory's file is rewritten",
      () => writeFile(p.join(bench.directory, 'a.dart'), 'second'),
    ),
    (
      'a file is added to a source directory',
      () => writeFile(p.join(bench.directory, 'b', 'c.dart'), 'added'),
    ),
    ('a source file is rewritten', () => writeFile(bench.file, 'other')),
  ]) {
    test('A kernel asked for after $change is compiled again, and the kernel '
        'before it is removed', () async {
      final String before = await bench.cache().kernel();
      await changed();
      final String after = await bench.cache().kernel();
      expect(after, isNot(before));
      expect(await bench.compiles(), 2);
      expect(await bench.kept(), {p.basename(after), 'contender.claim'});
    });
  }

  test('A kernel asked for under another SDK is compiled again, and the '
      'kernel before it is removed', () async {
    final String before = await bench.cache().kernel();
    final String after = await bench.cache('3.14.0').kernel();
    expect(after, isNot(before));
    expect(await bench.compiles(), 2);
    expect(await bench.kept(), {p.basename(after), 'contender.claim'});
  });

  test('A compile that fails throws and keeps no kernel, so the next ask '
      'compiles again', () async {
    bench.failing = true;
    await expectLater(bench.cache().kernel(), throwsA(isA<StateError>()));
    expect(await bench.kept(), {'contender.claim'});
    bench.failing = false;
    final String kernel = await bench.cache().kernel();
    expect(await bench.compiles(), 2);
    expect(await File(kernel).readAsString(), 'kernel 2');
  });

  property(
    'Over any run of asks and changes to the sources, a kernel is compiled '
    'at an ask alone where the sources have changed since the kernel kept, '
    'and every ask names a kernel of the sources as they stand.',
    (Draw draw) async {
      final List<_Step> steps = draw(
        .list(.element(_Step.values), minLength: 1, maxLength: 11),
        label: 'steps',
      );
      await inTemp((Directory temp) async {
        final _Bench bench = .new(temp);
        final String source = p.join(bench.directory, 'a.dart');
        await writeFile(source, 'first');
        await writeFile(bench.file, 'packages');
        final Map<String, String> kernels = {};
        String? kept;
        int edits = 0;
        int rewrites = 0;
        int adds = 0;
        int compiles = 0;
        for (final _Step step in steps) {
          switch (step) {
            case .ask:
              final String state = [
                await File(source).readAsString(),
                await File(bench.file).readAsString(),
                '$adds',
              ].join(' ');
              final String kernel = await bench.cache().kernel();
              if (state != kept) {
                compiles++;
                kept = state;
              }
              expect(await bench.compiles(), compiles);
              expect(kernels.putIfAbsent(state, () => kernel), kernel);
              expect(await bench.kept(), {
                p.basename(kernel),
                'contender.claim',
              });
            case .edit:
              await writeFile(source, 'edit ${++edits}');
            case .rewrite:
              await writeFile(bench.file, 'packages ${++rewrites}');
            case .restore:
              await writeFile(source, 'first');
            case .add:
              await writeFile(p.join(bench.directory, '${++adds}.dart'), '');
          }
        }
      });
    },
    settings: .new(runs: 20),
  );
}

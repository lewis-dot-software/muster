import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/loads.dart';
import '../support/markdown.dart';
import '../support/write_file.dart';

/// The git source of muster's dependency in an install block, which a
/// fresh package in a test takes by its path in place of.
final RegExp _gitSource = .new(r'    git:\n      url: .*\n      ref: (.*)\n');

/// The SDK version a load's print names, which turns on the SDK on `PATH`.
final RegExp _sdk = .new(r'resolved by \S+');

/// The code of each block of [language] in [markdown], in order.
List<String> _blocks(String markdown, String language) => [
  for (final FencedBlock block in fencedBlocks(markdown))
    if (block.language == language) block.code,
];

/// The text of the file at [segments] under muster's root.
Future<String> _read(List<String> segments) async =>
    File(p.joinAll([await musterRoot(), ...segments])).readAsString();

/// An event of `dart test`'s JSON reporter, by its type.
enum _Event {
  /// A test's failure, its message under `error`.
  error('error'),

  /// A test's print, its text under `message`.
  print('message');

  const _Event(this.field);

  /// The key the event's text sits under.
  final String field;
}

/// The text of each [event] a `dart test --reporter json` [run] reported,
/// in order.
List<String> _reported(ProcessResult run, _Event event) => [
  for (final String line in LineSplitter.split(run.stdout as String))
    if (jsonDecode(line) case final Map<String, Object?> json
        when json['type'] == event.name)
      json[event.field]! as String,
];

void main() {
  group('The quickstart', () {
    late final String quickstart;
    late final String readme;

    setUpAll(() async {
      quickstart = await _read(['docs', 'quickstart.md']);
      readme = await _read(['README.md']);
    });

    test("quotes the example's manifest verbatim, as the README does, and its test settings.", () async {
      final String manifest = await _read(['example', 'muster.yaml']);
      expect(_blocks(quickstart, 'yaml')[1], manifest);
      expect(_blocks(readme, 'yaml')[1], manifest);
      expect(
        await _read(['example', 'dart_test.yaml']),
        endsWith(_blocks(quickstart, 'yaml')[2]),
      );
    });

    test("quotes the example's test verbatim.", () async {
      expect(
        _blocks(quickstart, 'dart').single,
        await _read(['example', 'test', 'codebases_test.dart']),
      );
    });

    test(
      "installs as the README does, at a tag muster's repo holds.",
      () async {
        final String install = _blocks(quickstart, 'yaml').first;
        expect(_blocks(readme, 'yaml').first, install);
        final String tag = _gitSource.firstMatch(install)![1]!;
        final ProcessResult tagged = await Process.run('git', [
          'rev-parse',
          '--verify',
          'refs/tags/$tag',
        ], workingDirectory: await musterRoot());
        expect(tagged.exitCode, 0, reason: '${tagged.stderr}');
      },
    );

    test('loads both codebases in a fresh package as it says, writing the '
        'locks the example keeps.', () async {
      await inTemp((Directory temp) async {
        final String muster = await musterRoot();
        final String package = p.join(temp.path, 'fresh');
        final String install = _blocks(quickstart, 'yaml').first;
        expect(install, matches(_gitSource));
        await writeFile(
          p.join(package, 'pubspec.yaml'),
          'name: fresh\nenvironment:\n  sdk: ^3.13.0\n'
          '${install.replaceFirst(_gitSource, '    path: $muster\n')}',
        );
        await writeFile(
          p.join(package, 'muster.yaml'),
          _blocks(quickstart, 'yaml')[1],
        );
        await writeFile(
          p.join(package, 'dart_test.yaml'),
          _blocks(quickstart, 'yaml')[2],
        );
        await writeFile(
          p.join(package, 'test', 'codebases_test.dart'),
          _blocks(quickstart, 'dart').single,
        );
        final Map<String, String> environment = {
          ...hermetic(temp)..remove('MUSTER_MANIFESTS'),
          'MUSTER_CACHE': p.join(temp.path, 'cache'),
        };
        Future<ProcessResult> dart(List<String> arguments) => Process.run(
          'dart',
          arguments,
          workingDirectory: package,
          environment: environment,
          includeParentEnvironment: false,
        );
        // The package's own path stands as the page's `<package>`, however
        // the system spells it.
        final List<String> spellings = {
          Directory(package).resolveSymbolicLinksSync(),
          package,
        }.toList();
        String masked(String text) => spellings
            .fold(
              text,
              (String at, String path) => at.replaceAll(path, '<package>'),
            )
            .replaceAll(_sdk, 'resolved by an SDK');
        final List<String> texts = [
          for (final String text in _blocks(quickstart, 'text'))
            masked(text.trimRight()),
        ];

        final ProcessResult got = await dart(['pub', 'get', '--offline']);
        expect(got.exitCode, 0, reason: '${got.stdout}${got.stderr}');

        final ProcessResult first = await dart(['test', '--reporter', 'json']);
        expect(first.exitCode, isNot(0));
        expect(_reported(first, .error).map(masked), [texts[0]]);

        expect(_blocks(quickstart, 'sh').single.trim(), 'dart run muster lock');
        final ProcessResult lock = await dart(['run', 'muster', 'lock']);
        expect(lock.exitCode, 0, reason: '${lock.stdout}${lock.stderr}');
        expect(masked((lock.stdout as String).trimRight()), texts[1]);
        expect(
          {
            for (final FileSystemEntity kept in Directory(
              p.join(package, 'muster_locks'),
            ).listSync())
              p.basename(kept.path),
          },
          {
            for (final FileSystemEntity kept in Directory(
              p.join(muster, 'example', 'muster_locks'),
            ).listSync())
              p.basename(kept.path),
          },
        );

        final ProcessResult again = await dart(['test', '--reporter', 'json']);
        expect(again.exitCode, 0, reason: '${again.stdout}${again.stderr}');
        expect(_reported(again, .print).map(masked).join('\n'), texts[2]);
      });
    });
  });
}

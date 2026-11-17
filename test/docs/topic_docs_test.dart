import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/loads.dart';
import '../support/markdown.dart';
import '../support/surface.dart';

/// A link to a doc beside the quickstart, its file captured.
final RegExp _docLink = .new(r'\]\(([\w-]+\.md)\)');

/// A code span of markdown outside a fenced block, its code captured.
final RegExp _span = .new(r'`([^`\n]+)`');

/// An identifier of Dart's.
final RegExp _identifier = .new(r'[A-Za-z_$][\w$]*');

/// Every identifier inside a code span or a fenced block of [markdown].
Set<String> _codeIdentifiers(String markdown) => {
  for (final String code in [
    for (final FencedBlock block in fencedBlocks(markdown)) block.code,
    for (final RegExpMatch span in _span.allMatches(outsideFences(markdown)))
      span[1]!,
  ])
    for (final RegExpMatch word in _identifier.allMatches(code)) word[0]!,
};

void main() {
  group('The topic docs', () {
    late final String docs;
    late final Set<String> topics;
    late final Map<String, Set<String>> identifiers;

    setUpAll(() async {
      docs = p.join(await musterRoot(), 'docs');
      topics = {
        for (final RegExpMatch link in _docLink.allMatches(
          await File(p.join(docs, 'quickstart.md')).readAsString(),
        ))
          link[1]!,
      };
      identifiers = {
        for (final String topic in topics)
          if (File(p.join(docs, topic)) case final File file
              when file.existsSync())
            topic: _codeIdentifiers(await file.readAsString()),
      };
    });

    test('are each a doc that stands, linked from the quickstart.', () {
      expect(topics, isNotEmpty);
      expect(identifiers.keys, unorderedEquals(topics));
    });

    test('name every declaration muster exports in code.', () async {
      final Set<String> exported = {
        ...(await musterSurface()).exportNamespace.definedNames2.keys,
      };
      // Muster is exported, so a reading of no export fails.
      expect(exported, contains('Muster'));
      expect([
        for (final String name in exported)
          if (!identifiers.values.any(
            (Set<String> words) => words.contains(name),
          ))
            name,
      ], isEmpty);
    });
  });
}

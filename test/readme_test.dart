import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/loads.dart';

/// The text of the file at [segments] under muster's root.
Future<String> _read(List<String> segments) async =>
    File(p.joinAll([await musterRoot(), ...segments])).readAsString();

void main() {
  test("The README's manifest is `example/muster.yaml` verbatim.", () async {
    expect(
      await _read(['README.md']),
      contains('```yaml\n${await _read(['example', 'muster.yaml'])}```\n'),
    );
  });

  test("The README's test is the example's test verbatim.", () async {
    expect(
      await _read(['README.md']),
      contains(
        '```dart\n'
        '${await _read(['example', 'test', 'codebases_test.dart'])}'
        '```\n',
      ),
    );
  });
}

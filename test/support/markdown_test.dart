import 'package:test/test.dart';

import 'markdown.dart';

void main() {
  const String markdown =
      'Before `span`.\n'
      '```yaml\nkey: value\n```\n'
      'Between.\n'
      '```\nplain\n```\n'
      'After.\n';

  test('Reads each fenced block, its language and its code, in order.', () {
    expect(fencedBlocks(markdown), [
      (language: 'yaml', code: 'key: value\n'),
      (language: '', code: 'plain\n'),
    ]);
  });

  test('Cuts each fenced block out, leaving the prose around it.', () {
    expect(outsideFences(markdown), 'Before `span`.\n\nBetween.\n\nAfter.\n');
  });
}

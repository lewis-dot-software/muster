import 'package:test/test.dart';

import 'manifests.dart';

void main() {
  test('A text with a space at either end does not read bare, since a plain '
      'scalar drops it.', () {
    for (final String text in ['${'0' * 63} ', ' ${'0' * 63}', 'a ', ' a']) {
      expect(readsBare(text), isFalse, reason: text);
    }
  });
}

import 'package:test/test.dart';

import 'written_case.dart';

void main() {
  test('every case gives a value of its own case', () {
    for (final WrittenCase kind in WrittenCase.values) {
      expect(WrittenCase.of(kind.sample), kind);
    }
  });
}

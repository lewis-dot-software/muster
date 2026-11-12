import 'package:muster/muster.dart';
import 'package:test/test.dart';

import 'refusal_case.dart';

void main() {
  test('every case gives a refusal, each of its own case', () {
    for (final RefusalCase kind in RefusalCase.values) {
      expect(kind.samples, isNotEmpty, reason: kind.name);
      for (final LoadRefusal refusal in kind.samples) {
        expect(RefusalCase.of(refusal), kind);
      }
    }
  });
}

import 'package:muster/src/model/manifest_refusal.dart';
import 'package:test/test.dart';

import 'manifest_refusal_case.dart';
import 'written_case.dart';

void main() {
  test('every case gives a refusal, each of its own case', () {
    for (final ManifestRefusalCase kind in ManifestRefusalCase.values) {
      expect(kind.samples, isNotEmpty, reason: kind.name);
      for (final ManifestRefusal refusal in kind.samples) {
        expect(ManifestRefusalCase.of(refusal), kind);
      }
    }
  });

  test('a bad value is given of every case of what is written', () {
    expect({
      for (final ManifestRefusal refusal
          in ManifestRefusalCase.badValue.samples)
        WrittenCase.of(switch (refusal) {
          BadValue(:final written) => written,
          NotYaml() ||
          UnknownKey() ||
          MissingKey() => fail('a bad value sample that is $refusal'),
        }),
    }, WrittenCase.values.toSet());
  });
}

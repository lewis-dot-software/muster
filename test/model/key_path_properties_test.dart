import 'dart:convert';

import 'package:grit/grit.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';

/// A key drawn from text that a path could mistake: an empty one, a `.`, a
/// `"`, a `\`, a line break and Unicode's, among plain letters.
final Gen<String> _key = .string(alphabet: .of('ab."\\\n\u2028'));

/// [keys] as they would read joined by `.` and split again.
List<String> _resplit(List<String> keys) =>
    keys.isEmpty ? keys : keys.join('.').split('.');

/// Whether [a] and [b] hold the same keys in the same order.
bool _same(List<String> a, List<String> b) => jsonEncode(a) == jsonEncode(b);

void main() {
  property(
    'Two key paths are the same exactly when their keys are, an empty key '
    'and one holding a dot among them.',
    (Draw draw) {
      final List<String> a = draw(.list(_key), label: 'a');
      final List<String> b = draw(.list(_key), label: 'b');
      for (final List<String> other in [
        b,
        _resplit(a),
        [...a, ''],
        [...a],
      ]) {
        expect(
          pathOf(a) == pathOf(other),
          _same(a, other),
          reason: '${jsonEncode(a)} against ${jsonEncode(other)}',
        );
      }
    },
  );
}

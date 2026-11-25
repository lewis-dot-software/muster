import 'dart:convert';

import 'package:grit/grit.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';

/// A key drawn from text that a path could mistake: an empty one, a `.`, a
/// `"`, a `\`, a tab, a line break, a carriage return, a nul, a C1 control
/// and Unicode's line and paragraph separators, among plain letters.
final Gen<String> _key = .string(
  alphabet: .of('ab."\\\t\n\r\x00\x85\u2028\u2029'),
);

/// [keys] as they would read joined by `.` and split again.
List<String> _resplit(List<String> keys) =>
    keys.isEmpty ? keys : keys.join('.').split('.');

/// Whether [a] and [b] hold the same keys in the same order.
bool _same(List<String> a, List<String> b) => jsonEncode(a) == jsonEncode(b);

void main() {
  property(
    'MAN-19: Two key paths are the same exactly when their keys are, whatever '
    'a key holds, an empty key and ones holding a dot, a quote or a character '
    'that breaks a line among them.',
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

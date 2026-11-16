import 'package:muster/src/cli/cell.dart';
import 'package:test/test.dart';

void main() {
  group('a cell', () {
    final Map<String, (String, String)> cases = {
      'stands where it holds no tab, no line break and no opening quote, a '
          'space and a quote inside it among it': (
        '/a b/c"d',
        '/a b/c"d',
      ),
      'is quoted with a tab escaped': ('/a\tb', r'"/a\tb"'),
      'is quoted with a line break escaped': ('/a\nb\r', r'"/a\nb\r"'),
      "is quoted with Unicode's line breaks and a delete escaped": (
        '/a\u0085b\u2028c\u2029d\x7f',
        r'"/a\u0085b\u2028c\u2029d\u007f"',
      ),
      'is quoted with another control character escaped': (
        '/a\x07b\x1bc',
        r'"/a\u0007b\u001bc"',
      ),
      'is quoted where it opens on a quote, with the quote escaped': (
        '"a',
        r'"\"a"',
      ),
    };
    for (final MapEntry(key: String name, value: (String text, String given))
        in cases.entries) {
      test(name, () {
        expect(cell(text), given);
      });
    }
  });
}

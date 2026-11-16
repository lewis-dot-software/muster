import 'package:test/test.dart';

/// [out]'s lines, each split into its cells at its tabs, the empty one after
/// the last line's break left out.
List<List<String>> linesOf(String out) {
  final List<String> lines = out.split('\n');
  expect(lines.last, isEmpty);
  return [
    for (final String line in lines.sublist(0, lines.length - 1))
      line.split('\t'),
  ];
}

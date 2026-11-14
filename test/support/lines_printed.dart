import 'dart:async';

/// Each line [run] prints, caught before it reaches the test's output.
List<String> linesPrinted(void Function() run) {
  final List<String> lines = [];
  runZoned(
    run,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, String line) => lines.add(line),
    ),
  );
  return lines;
}

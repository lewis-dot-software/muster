import 'package:glados/glados.dart';

import 'shrinking_at_most.dart';

/// How many shrinks glados's walk of [drawn] tries, each failing as a
/// property that never holds does, so the walk goes as deep as it can.
int _tried(Shrinkable<Object?> drawn) {
  int tried = 0;
  Shrinkable<Object?> at = drawn;
  outer:
  while (true) {
    for (final Shrinkable<Object?> shrunk in at.shrink()) {
      tried++;
      at = shrunk;
      continue outer;
    }
    return tried;
  }
}

void main() {
  final Generator<List<int>> long = any.listWithLength(
    10,
    any.intInRange(0, 100),
  );

  Glados(any.intInRange(0, 10), .new(numRuns: 20)).test(
    'A draw shrinks at most the tries it is bounded to, however its shrinks '
    'nest.',
    (int tries) {
      expect(_tried(long(Random(tries), 10)), greaterThan(tries));
      expect(_tried(long.shrinkingAtMost(tries)(Random(tries), 10)), tries);
    },
  );
}

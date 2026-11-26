import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/loads.dart';
import '../support/manifests.dart';
import '../support/spy_runner.dart';
import '../support/write_file.dart';

/// How a load is given its manifests.
enum _Given {
  /// Each one named by its caller.
  named,

  /// The first as the `muster.yaml` at the consumer's root, and the rest in
  /// `MUSTER_MANIFESTS`.
  listed,
}

void main() {
  property("MAN-24: A name met in two of a load's manifests refuses the load, "
      'naming it, the manifest it is first met in and the one it is met in '
      'again, whether each manifest is named, at the root or listed, and where '
      'one manifest is given twice.', (Draw draw) {
    final List<List<Codebase>> manifests = draw(
      .list(
        anyCodebases(names: .element(['a', 'b', 'c', 'd', 'e', 'f'])),
        minLength: 2,
        maxLength: 4,
      ),
      label: 'manifests',
    );
    final _Given given = draw(.element(_Given.values), label: 'given');
    final bool again = draw(.boolean(), label: 'again');
    final Writing writing = draw(.element(Writing.values), label: 'writing');
    return inTemp((Directory temp) async {
      final List<String> paths = [
        for (final (int i, List<Codebase> _) in manifests.indexed)
          switch ((given, i)) {
            (.listed, 0) => atRoot(temp),
            (.named || .listed, _) => p.join(temp.path, 'm$i', 's$i.yaml'),
          },
      ];
      final List<int> read = [
        for (final (int i, List<Codebase> _) in manifests.indexed) i,
        if (again) 0,
      ];
      // Each manifest's codebases, the first and the last given one name
      // between them where no name is met twice otherwise: the first met
      // before the last, given the last too, or else the last's own, given
      // the first too.
      final List<List<Codebase>> written = [...manifests];
      final Iterable<String> names = [
        for (final int i in read)
          for (final Codebase codebase in written[i]) codebase.name.name,
      ];
      if (names.toSet().length == names.length) {
        final Iterable<Codebase> before = written
            .take(written.length - 1)
            .expand((List<Codebase> c) => c);
        switch ((before.firstOrNull, written.last.firstOrNull)) {
          case (final Codebase met, _):
            written[written.length - 1] = [...written.last, met];
          case (null, final Codebase last):
            written[0] = [last];
          case (null, null):
            final Codebase stub = Hosted(
              hosted('a', 'args', '2.7.0', .alone, .dart),
            );
            written[0] = [stub];
            written[written.length - 1] = [stub];
        }
      }
      for (final (int i, String path) in paths.indexed) {
        await writeFile(
          path,
          renderManifest(written[i].map(anyEntryOf).toList(), writing: writing),
        );
      }
      final Map<String, int> seen = {};
      late final _Twice twice;
      search:
      for (final int i in read) {
        for (final Codebase codebase in written[i]) {
          if (seen[codebase.name.name] case final int first) {
            twice = (name: codebase.name.name, first: first, second: i);
            break search;
          }
          seen[codebase.name.name] = i;
        }
      }
      final (:String name, :int first, :int second) = twice;
      final SpyRunner runner = .new(hermetic(temp));
      final Load load = await switch (given) {
        .named => loaderIn(
          temp,
          runner,
        ).load(named: [for (final int i in read) paths[i]]),
        .listed => loaderIn(
          temp,
          runner,
          variables: {
            'MUSTER_MANIFESTS': [for (final int i in read.skip(1)) paths[i]]
                .join(':'),
          },
        ).load(),
      };
      expect(
        load,
        refusedFor(
          isA<CodebaseNamedTwice>()
              .having((r) => r.name.name, 'name', name)
              .having((r) => r.first.path, 'first', paths[first])
              .having((r) => r.second.path, 'second', paths[second]),
        ),
      );
      expect(runner.commands, isEmpty);
    });
  }, settings: .new(runs: 100));
}

/// The first name met twice: [name], the index of the manifest it is first
/// met in, [first], and of the one it is met in again, [second].
typedef _Twice = ({String name, int first, int second});

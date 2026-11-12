import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/manifest_merge.dart';
import 'package:muster/src/model/merge_manifests.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';

void main() {
  final String hash = 'ab' * 20;

  test('the manifests join into their codebases, in their order, each '
      'beside the manifest that named it', () {
    expect(
      mergeManifests([
        .new([Git(codebase('b', '/srv/b.git', hash, '.', .dart))]),
        .new([]),
        .new([
          Git(codebase('a', '/srv/a.git', hash, '.', .dart)),
          Git(codebase('c', '/srv/c.git', hash, '.', .flutter)),
          Hosted(hosted('d', 'args', '2.7.0', .alone, .dart)),
        ]),
      ]),
      isA<Merged>().having(
        (m) => [
          for (final c in m.codebases) (c.codebase.name.name, c.manifest),
        ],
        'names',
        [('b', 0), ('a', 2), ('c', 2), ('d', 2)],
      ),
    );
  });

  test('a name met twice refuses, naming it and both manifests, whatever '
      'kind each codebase is', () {
    expect(
      mergeManifests([
        .new([Git(codebase('a', '/srv/a.git', hash, '.', .dart))]),
        .new([Git(codebase('b', '/srv/b.git', hash, '.', .dart))]),
        .new([Hosted(hosted('a', 'args', '2.7.0', .alone, .dart))]),
      ]),
      isA<NamedTwice>()
          .having((n) => n.name.name, 'name', 'a')
          .having((n) => n.first, 'first', 0)
          .having((n) => n.second, 'second', 2),
    );
  });
}

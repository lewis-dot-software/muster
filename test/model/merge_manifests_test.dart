import 'package:muster/src/model/manifest_merge.dart';
import 'package:muster/src/model/merge_manifests.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';

void main() {
  final String hash = 'ab' * 20;

  test('the manifests join into their codebases, in their order', () {
    expect(
      mergeManifests([
        .new([codebase('b', '/srv/b.git', hash, '.', .dart)]),
        .new([]),
        .new([
          codebase('a', '/srv/a.git', hash, '.', .dart),
          codebase('c', '/srv/c.git', hash, '.', .flutter),
        ]),
      ]),
      isA<Merged>().having(
        (m) => m.codebases.map((c) => c.name.name),
        'names',
        ['b', 'a', 'c'],
      ),
    );
  });

  test('a name met twice refuses, naming it and both manifests', () {
    expect(
      mergeManifests([
        .new([codebase('a', '/srv/a.git', hash, '.', .dart)]),
        .new([codebase('b', '/srv/b.git', hash, '.', .dart)]),
        .new([codebase('a', '/srv/other.git', hash, '.', .dart)]),
      ]),
      isA<NamedTwice>()
          .having((n) => n.name.name, 'name', 'a')
          .having((n) => n.first, 'first', 0)
          .having((n) => n.second, 'second', 2),
    );
  });
}

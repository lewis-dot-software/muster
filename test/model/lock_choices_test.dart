import 'package:grit/grit.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/choose_unnamed.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/locks_lacking.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/partial_lock_path.dart';
import 'package:muster/src/model/unnamed_lock.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/manifests.dart';

final LocksDirectory _locks = .beside(.parse('/m/muster.yaml', .posix)!);

/// The file name of each kept lock of [codebases]' packages.
List<String> _namedFiles(List<GitCodebase> codebases) => [
  for (final GitCodebase codebase in codebases)
    for (final Package package in Package.values)
      p.posix.basename(keptLockOf(_locks, Git(codebase), package).path),
];

void main() {
  property('Of the files a locks directory lists, every kept lock and partial '
      'no codebase names is chosen for removal, in their file names\' order, '
      'and nothing else is.', (Draw draw) {
    final List<GitCodebase> named = draw(anyGitCodebases(), label: 'named');
    final List<GitCodebase> others = draw(anyGitCodebases(), label: 'others');
    final List<String> strays = draw(
      .list(.element(['a.lock', 'b.example.lock', 'README.md', '.lock'])),
      label: 'strays',
    );
    final List<String> listed = [
      for (final String name in [
        ..._namedFiles(named),
        ..._namedFiles(others),
        ...strays,
      ]) ...[name, '$name.partial'],
    ];
    final List<UnnamedLock> unnamed = chooseUnnamed(
      _locks,
      listed,
      named.map(Git.new),
    );
    final Set<String> keep = {
      for (final String name in _namedFiles(named)) ...[name, '$name.partial'],
    };
    expect(
      [
        for (final UnnamedLock chosen in unnamed)
          p.posix.basename(switch (chosen) {
            UnnamedKept(:final KeptLockPath lock) => lock.path,
            UnnamedPartial(:final PartialLockPath partial) => partial.path,
          }),
      ],
      [
        for (final String name in [...listed]..sort())
          if ((listedKeptLock(_locks, name) != null ||
                  PartialLockPath.listed(_locks, name) != null) &&
              !keep.contains(name))
            name,
      ],
    );
  });

  test('a file named .lock alone, or with no .lock before .partial, is '
      'neither a kept lock nor a partial', () {
    for (final String name in ['.lock', '.lock.partial', 'a.partial']) {
      expect(listedKeptLock(_locks, name), isNull);
      expect(PartialLockPath.listed(_locks, name), isNull);
    }
  });

  test('the packages lacking a kept lock are those the commit holds with no '
      'lock of its own and none kept, in their order', () {
    expect(locksLacking((packages: {.root, .example}, locked: {}), {}), [
      Package.root,
      Package.example,
    ]);
    expect(locksLacking((packages: {.root, .example}, locked: {.root}), {}), [
      Package.example,
    ]);
    expect(
      locksLacking((packages: {.root, .example}, locked: {}), {.example}),
      [Package.root],
    );
    expect(locksLacking((packages: {.root}, locked: {}), {.example}), [
      Package.root,
    ]);
    expect(locksLacking((packages: {.root}, locked: {.root}), {}), isEmpty);
  });
}

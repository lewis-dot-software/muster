import 'package:glados/glados.dart';
import 'package:muster/src/model/choose_unnamed.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/locks_lacking.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/partial_lock_path.dart';
import 'package:muster/src/model/unnamed_locks.dart';
import 'package:path/path.dart' as p;

import '../support/manifests.dart';

final LocksDirectory _locks = .beside(.parse('/m/muster.yaml', .posix)!);

/// The file name of each kept lock of [codebases]' packages.
List<String> _namedFiles(List<GitCodebase> codebases) => [
  for (final GitCodebase codebase in codebases)
    for (final Package package in Package.values)
      p.posix.basename(KeptLockPath.of(_locks, codebase, package).path),
];

void main() {
  Glados3(
    any.gitCodebases(),
    any.gitCodebases(),
    any.list(any.choose(['a.lock', 'b.example.lock', 'README.md', '.lock'])),
  ).test('Of the files a locks directory lists, every kept lock and partial no '
      'codebase names is chosen for removal, and nothing else is.', (
    List<GitCodebase> named,
    List<GitCodebase> others,
    List<String> strays,
  ) {
    final List<String> listed = [
      for (final String name in [
        ..._namedFiles(named),
        ..._namedFiles(others),
        ...strays,
      ]) ...[name, '$name.partial'],
    ];
    final UnnamedLocks unnamed = chooseUnnamed(_locks, listed, named);
    final Set<String> keep = {
      for (final String name in _namedFiles(named)) ...[name, '$name.partial'],
    };
    final Set<String> lockShaped = {
      for (final String name in listed)
        if (KeptLockPath.listed(_locks, name) != null ||
            PartialLockPath.listed(_locks, name) != null)
          name,
    };
    expect({
      for (final KeptLockPath lock in unnamed.locks)
        p.posix.basename(lock.path),
      for (final PartialLockPath partial in unnamed.partials)
        p.posix.basename(partial.path),
    }, lockShaped.difference(keep));
  });

  test('a file named .lock alone, or with no .lock before .partial, is '
      'neither a kept lock nor a partial', () {
    for (final String name in ['.lock', '.lock.partial', 'a.partial']) {
      expect(KeptLockPath.listed(_locks, name), isNull);
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

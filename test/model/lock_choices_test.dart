import 'package:grit/grit.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/choose_unnamed.dart';
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
List<String> _namedFiles(List<Codebase> codebases) => [
  for (final Codebase codebase in codebases)
    for (final Package package in Package.values)
      p.posix.basename(keptLockOf(_locks, codebase, package).path),
];

/// Whether [name] is a kept lock's file name: a stem of its own, then
/// `.lock`.
bool _isKept(String name) =>
    name.length > '.lock'.length && name.endsWith('.lock');

/// Whether [name] is a partial's file name: a kept lock's, then `.partial`.
bool _isPartial(String name) =>
    name.endsWith('.partial') &&
    _isKept(name.substring(0, name.length - '.partial'.length));

void main() {
  property('MAN-18: Of the files a locks directory lists, every kept lock and '
      'partial no codebase names is chosen for removal, in their file names\' '
      'order, and nothing else is.', (Draw draw) {
    final List<Codebase> named = draw(anyCodebases(), label: 'named');
    final List<Codebase> others = draw(anyCodebases(), label: 'others');
    final List<String> strays = draw(
      .list(
        .element([
          'a.lock',
          'b.example.lock',
          'README.md',
          '.lock',
          'a.partial',
          'a.lock.bak',
        ]),
      ),
      label: 'strays',
    );
    final List<String> listed = [
      for (final String name in [
        ..._namedFiles(named),
        ..._namedFiles(others),
        ...strays,
      ]) ...[name, '$name.partial'],
    ];
    final List<UnnamedLock> unnamed = chooseUnnamed(_locks, listed, named);
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
          if ((_isKept(name) || _isPartial(name)) && !keep.contains(name)) name,
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

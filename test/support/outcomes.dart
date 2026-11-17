import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/lock_outcome.dart';
import 'package:muster/src/model/lock_removal.dart';
import 'package:muster/src/model/package.dart';

import 'example_case.dart';
import 'loads.dart';
import 'manifests.dart';
import 'outcome_case.dart';

/// A `codebase` beside the `outcome` a load gave it.
typedef DrawnOutcome = (GitCodebase codebase, FetchOutcome outcome);

/// A `codebase` beside the `outcome` a lock gave it.
typedef DrawnLockOutcome = (GitCodebase codebase, LockOutcome outcome);

/// A codebase beside the outcome a load gave it, of any [OutcomeCase] and
/// any [ExampleCase], its URL, its root and every path it carries drawn
/// holding a tab, a line break or a quote where it may hold one.
final Gen<DrawnOutcome> anyOutcome = .build((Draw draw) {
  final GitCodebase codebase = draw(
    anyGitCodebase(urls: _awkwardUrl, roots: _awkwardRoot),
  );
  final OutcomeCase kind = draw(.element(OutcomeCase.values));
  return (
    codebase,
    kind.outcome(
      codebase,
      exitCode: draw(.integer(min: 1, max: 255)),
      output: draw(.element(['', 'fatal: no such repo\n', 'a\nb'])),
      package: draw(.element(Package.values)),
      executable: draw(.element(Executable.values)),
      under: draw(.element(_directories)),
      example: draw(.element(ExampleCase.values)),
      outside: draw(.element(_outsides)),
    ),
  );
});

/// A codebase beside the outcome a lock gave it: the kept lock an
/// [Unlocked] outcome lacked written, none for a [Fetched] one, and any
/// other outcome's failure.
final Gen<DrawnLockOutcome> anyLockOutcome = anyOutcome.map(
  (DrawnOutcome drawn) => (
    drawn.$1,
    switch (drawn.$2) {
      Fetched() => const LocksWritten([]),
      Unlocked(:final KeptLockPath lock) => LocksWritten([lock]),
      final ActFailure failure => LockFailed(failure),
    },
  ),
);

/// A kept lock removed, or its removal failed, its directory and its file
/// name drawn holding a tab, a line break or a quote.
final Gen<LockRemoval> anyRemoval = .build((Draw draw) {
  final String under = draw(.element(_directories));
  final String name = draw(
    .element(['gone', 'go\tne', 'go\nne', '"gone', 'go\u2028ne']),
  );
  final KeptLockPath lock = listedKeptLock(
    locksBeside('$under/muster.yaml'),
    '$name.lock',
  )!;
  return draw(.boolean())
      ? LockRemoved(lock)
      : RemovalFailed(.new(lock.path, 'Permission denied'));
});

/// A git URL, a tab, a space or a quote before it where one is drawn.
final Gen<String> _awkwardUrl = .build((Draw draw) {
  final String url = draw(anyGitUrl);
  return '${draw(.element(_inLine))}$url';
});

/// A root inside its repo, a directory below it named with a tab, a space
/// or a quote where one is drawn.
final Gen<String> _awkwardRoot = .build((Draw draw) {
  final String root = draw(anyNormalRoot);
  final String inner = draw(.element(_inLine));
  return inner.isEmpty
      ? root
      : root == '.'
      ? 'a${inner}b'
      : '$root/a${inner}b';
});

/// What a URL or a root may hold of the characters a cell quotes, and a
/// space, which it does not.
const List<String> _inLine = ['', '\t', ' ', '"'];

/// The directories a checkout, a manifest or a store's path stands under,
/// plain, holding a tab or a line break, or opening on a quote.
const List<String> _directories = [
  '/consumer',
  '/con\tsumer',
  '/con\nsumer',
  '/con\rsumer',
  '/con\u2028sumer',
  '/con\x7fsumer',
  '"consumer',
];

/// The paths an unresolved example's pubspec may write for its dependency.
const List<String> _outsides = ['../outside', '../out\tside\n'];

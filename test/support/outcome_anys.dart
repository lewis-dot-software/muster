import 'package:glados/glados.dart';
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

/// The generators the command line's property tests draw from.
extension OutcomeAnys on Any {
  /// A codebase beside the outcome a load gave it, of any [OutcomeCase] and
  /// any [ExampleCase], its URL, its root and every path it carries drawn
  /// holding a tab, a line break or a quote where it may hold one.
  Generator<(GitCodebase, FetchOutcome)> get outcome => combine9(
    gitCodebase(urls: _awkwardUrl, roots: _awkwardRoot),
    choose(OutcomeCase.values),
    intInRange(1, 256),
    choose(['', 'fatal: no such repo\n', 'a\nb']),
    choose(Package.values),
    choose(Executable.values),
    choose(_directories),
    choose(ExampleCase.values),
    choose(_outsides),
    (
      GitCodebase codebase,
      OutcomeCase kind,
      int exitCode,
      String output,
      Package package,
      Executable executable,
      String under,
      ExampleCase example,
      String outside,
    ) => (
      codebase,
      kind.outcome(
        codebase,
        exitCode: exitCode,
        output: output,
        package: package,
        executable: executable,
        under: under,
        example: example,
        outside: outside,
      ),
    ),
  );

  /// A codebase beside the outcome a lock gave it: the kept lock an
  /// [Unlocked] outcome lacked written, none for a [Fetched] one, and any
  /// other outcome's failure.
  Generator<(GitCodebase, LockOutcome)> get lockOutcome => outcome.map(
    ((GitCodebase, FetchOutcome) drawn) => (
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
  Generator<LockRemoval> get removal => combine3(
    choose(_directories),
    choose(['gone', 'go\tne', 'go\nne', '"gone', 'go\u2028ne']),
    any.bool,
    (String under, String name, bool removed) {
      final KeptLockPath lock = listedKeptLock(
        locksBeside('$under/muster.yaml'),
        '$name.lock',
      )!;
      return removed
          ? LockRemoved(lock)
          : RemovalFailed(StoreFailed(lock.path, 'Permission denied'));
    },
  );

  /// A git URL, a tab, a space or a quote before it where one is drawn.
  Generator<String> get _awkwardUrl => combine2(
    gitUrl,
    choose(_inLine),
    (String url, String head) => '$head$url',
  );

  /// A root inside its repo, a directory below it named with a tab, a space
  /// or a quote where one is drawn.
  Generator<String> get _awkwardRoot => combine2(
    normalRoot,
    choose(_inLine),
    (String root, String inner) => inner.isEmpty
        ? root
        : root == '.'
        ? 'a${inner}b'
        : '$root/a${inner}b',
  );
}

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

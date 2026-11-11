import 'package:glados/glados.dart';
import 'package:muster/src/model/at_commit.dart';
import 'package:muster/src/model/at_commit_files.dart';
import 'package:muster/src/model/choose_locks.dart';
import 'package:muster/src/model/lock_choice.dart';
import 'package:muster/src/model/lock_source.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/package_file.dart';
import 'package:muster/src/model/read_at_commit.dart';
import 'package:muster/src/model/repo_path.dart';
import 'package:muster/src/model/repo_root.dart';

import '../support/manifests.dart';

/// A codebase's root, which of the files [atCommitFiles] names its commit
/// lists, by index, other files it lists beside them, and which packages
/// have a kept lock.
typedef _Draw = ({
  RepoRoot root,
  Set<int> listed,
  List<String> others,
  Set<Package> kept,
});

final Generator<_Draw> _draw = any.combine4(
  any.normalRoot,
  any.set(any.intInRange(0, 3)),
  any.list(any.choose(['README.md', 'example/README.md', 'lib/pubspec.lock'])),
  any.set(any.choose(Package.values)),
  (String root, Set<int> listed, List<String> others, Set<Package> kept) =>
      (root: .parse(root)!, listed: listed, others: others, kept: kept),
);

void main() {
  Glados(_draw, ExploreConfig(numRuns: 300)).test(
    'Each package a git codebase resolves, its `root` and an `example/` with '
    'a pubspec of its own, takes the `pubspec.lock` its commit holds there, '
    'else its kept lock, and with neither the codebase returns `Unlocked`.',
    (_Draw draw) {
      final List<RepoPath> files = atCommitFiles(draw.root);
      final Set<RepoPath> listed = {
        for (final int i in draw.listed) files[i],
        for (final String other in draw.others)
          Package.root.inRepo(draw.root).join(other),
      };
      bool lists(Package package, PackageFile file) =>
          listed.contains(package.fileInRepo(draw.root, file));
      final List<Package> packages = [
        .root,
        if (lists(.example, .pubspec)) .example,
      ];
      final AtCommit atCommit = readAtCommit(draw.root, listed);
      expect(atCommit.packages, packages.toSet());
      final List<Package> lacking = [
        for (final Package package in packages)
          if (!lists(package, .lock) && !draw.kept.contains(package)) package,
      ];
      final LockChoice choice = chooseLocks(atCommit, draw.kept);
      switch (choice) {
        case LocksChosen(:final Map<Package, LockSource> locks):
          expect(lacking, isEmpty);
          expect(locks, {
            for (final Package package in packages)
              package: lists(package, .lock)
                  ? LockSource.committed
                  : LockSource.kept,
          });
          expect(locks.keys, packages);
        case LockLacking(:final Package package):
          expect(package, lacking.first);
      }
    },
  );
}

import 'package:grit/grit.dart';
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
import 'package:test/test.dart';

import '../support/manifests.dart';

void main() {
  property(
    'Each package a git codebase resolves, its `root` and an `example/` with '
    'a pubspec of its own, takes the `pubspec.lock` its commit holds there, '
    'else its kept lock, and with neither the codebase returns `Unlocked`.',
    (Draw draw) {
      final RepoRoot root = .parse(draw(anyNormalRoot, label: 'root'))!;
      final Set<int> indices = draw(
        .set(.integer(min: 0, max: 2)),
        label: 'indices',
      );
      final List<String> others = draw(
        .list(.element(['README.md', 'example/README.md', 'lib/pubspec.lock'])),
        label: 'others',
      );
      final Set<Package> kept = draw(
        .set(.element(Package.values)),
        label: 'kept',
      );
      final List<RepoPath> files = atCommitFiles(root);
      final Set<RepoPath> listed = {
        for (final int i in indices) files[i],
        for (final String other in others)
          Package.root.inRepo(root).join(other),
      };
      bool lists(Package package, PackageFile file) =>
          listed.contains(package.fileInRepo(root, file));
      final List<Package> packages = [
        .root,
        if (lists(.example, .pubspec)) .example,
      ];
      final AtCommit atCommit = readAtCommit(root, listed);
      expect(atCommit.packages, packages.toSet());
      final List<Package> lacking = [
        for (final Package package in packages)
          if (!lists(package, .lock) && !kept.contains(package)) package,
      ];
      final LockChoice choice = chooseLocks(atCommit, kept);
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
    settings: .new(runs: 300),
  );
}

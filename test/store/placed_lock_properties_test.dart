import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/package.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git.dart';
import '../support/loads.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/spy_runner.dart';
import '../support/write_file.dart';

/// The locks a package has for its load to choose from.
enum _Locks {
  /// Its commit's `pubspec.lock` alone.
  committed,

  /// Its kept lock alone.
  kept,

  /// Both its commit's `pubspec.lock` and its kept lock.
  both;

  /// Whether its commit holds a `pubspec.lock`.
  bool get inCommit => switch (this) {
    .committed || .both => true,
    .kept => false,
  };

  /// Whether a kept lock stands beside its manifest.
  bool get beside => switch (this) {
    .kept || .both => true,
    .committed => false,
  };
}

/// The lock a commit holds, told from a kept one by its opening comment.
const String _committed = '# committed\n$lockText';

/// A kept lock, told from a commit's by its opening comment.
const String _kept = '# kept\n$lockText';

void main() {
  property('MAN-25: A git checkout holds the lock chosen for each package it '
      "resolves as its `pubspec.lock`, its commit's before its kept lock, its "
      '`root` and its `example/` alike.', (Draw draw) async {
    for (final bool nested in [false, true]) {
      for (final _Locks root in _Locks.values) {
        for (final _Locks? example in [..._Locks.values, null]) {
          await _placed(nested, root, example);
        }
      }
    }
  }, settings: .new(runs: 1));
}

/// A load of a git codebase whose package sits in `pkg` where [nested] holds
/// and at its repo's top otherwise, its package's locks as [root] says, and
/// an example's as [example] says where one stands.
Future<void> _placed(bool nested, _Locks root, _Locks? example) =>
    inTemp((Directory temp) async {
      final String drawn = 'nested $nested, root $root, example $example';
      final SpyRunner runner = .new(hermetic(temp));
      final Origin origin = await .make(temp, runner);
      final String at = nested ? 'pkg' : '.';
      final Map<Package, _Locks> locks = {
        .root: root,
        if (example case final _Locks drawn) .example: drawn,
      };
      String dirOf(Package package) => switch (package) {
        .root => at,
        .example => '$at/example',
      };
      final GitCodebase codebase = await branchedCodebase(origin, 'app', {
        for (final MapEntry(key: Package package, value: _Locks drawn)
            in locks.entries) ...{
          ...packageFiles(
            switch (package) {
              .root => 'app',
              .example => 'app_example',
            },
            at: dirOf(package),
            locked: false,
          ),
          if (drawn.inCommit)
            p.posix.normalize('${dirOf(package)}/pubspec.lock'): _committed,
        },
      }, root: at);
      final String manifest = atRoot(temp);
      await writeManifest(manifest, [codebase]);
      for (final MapEntry(key: Package package, value: _Locks drawn)
          in locks.entries) {
        if (drawn.beside) {
          final KeptLockPath kept = keptLockOf(
            locksBeside(manifest),
            Git(codebase),
            package,
          );
          await writeFile(kept.path, _kept);
        }
      }
      final String checkout = checkoutAt(temp, 'app');
      expect(
        await loaderIn(temp, runner).load(),
        loadedWith({'app': fetchedAt(p.normalize(p.join(checkout, at)))}),
        reason: drawn,
      );
      for (final MapEntry(key: Package package, value: _Locks drawn)
          in locks.entries) {
        expect(
          await File(p.join(checkout, dirOf(package), 'pubspec.lock'))
              .readAsString(),
          drawn.inCommit ? _committed : _kept,
          reason: '$drawn, $package',
        );
      }
    });

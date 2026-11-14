import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/codebase_name.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/lock_key.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/manifest_path.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/package_path.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';

void main() {
  final CodebaseName app = .parse('app')!;

  test('a checkout stands in .dart_tool/muster/ under its root, its stamp '
      'beside it', () {
    final CheckoutPath checkout = .of(.new('/work/tool', .posix), app);
    expect(checkout.path, '/work/tool/.dart_tool/muster/app');
    expect(checkout.stamp.path, '/work/tool/.dart_tool/muster/app.stamp');
  });

  test('a checkout under a Windows root is joined in its separators', () {
    final CheckoutPath checkout = .of(.new(r'C:\work\tool', .windows), app);
    expect(checkout.path, r'C:\work\tool\.dart_tool\muster\app');
    expect(checkout.stamp.path, r'C:\work\tool\.dart_tool\muster\app.stamp');
    expect(
      packageIn(checkout, .parse('pkgs/a')!, .root).packageConfig.path,
      r'C:\work\tool\.dart_tool\muster\app\pkgs\a\.dart_tool'
      r'\package_config.json',
    );
    expect(
      packageIn(checkout, .parse('pkgs/a')!, .example).lock.path,
      r'C:\work\tool\.dart_tool\muster\app\pkgs\a\example\pubspec.lock',
    );
  });

  test('a package sits at its root inside the checkout, the example under '
      'it, with its lock and package config inside', () {
    final CheckoutPath checkout = .of(.new('/c', .posix), app);
    final PackagePath top = packageIn(checkout, .top, .root);
    expect(top.path, '/c/.dart_tool/muster/app');
    expect(top.lock.path, '/c/.dart_tool/muster/app/pubspec.lock');
    expect(
      top.packageConfig.path,
      '/c/.dart_tool/muster/app/.dart_tool/package_config.json',
    );
    expect(
      packageIn(checkout, .parse('pkgs/a')!, .example).path,
      '/c/.dart_tool/muster/app/pkgs/a/example',
    );
  });

  test('a package\'s files in its repo are relative to the top, in / '
      'separators', () {
    expect(Package.root.fileInRepo(.top, .lock).path, 'pubspec.lock');
    expect(
      Package.example.fileInRepo(.top, .pubspec).path,
      'example/pubspec.yaml',
    );
    expect(
      Package.example.fileInRepo(.parse('a/b')!, .lock).path,
      'a/b/example/pubspec.lock',
    );
  });

  test('a manifest\'s path ends .yaml after a stem of its own', () {
    expect(
      ManifestPath.parse('/c/muster.yaml', .posix)?.path,
      '/c/muster.yaml',
    );
    expect(ManifestPath.parse('/c/.yaml', .posix), isNull);
    expect(ManifestPath.parse('/c/muster.yml', .posix), isNull);
    expect(ManifestPath.parse('/c/muster', .posix), isNull);
  });

  test('a manifest keeps its locks in <stem>_locks/ beside it', () {
    expect(
      LocksDirectory.beside(.parse('/c/muster.yaml', .posix)!).path,
      '/c/muster_locks',
    );
    expect(
      LocksDirectory.beside(.parse(r'C:\c\bench.yaml', .windows)!).path,
      r'C:\c\bench_locks',
    );
  });

  test('a kept lock is <name>-<key>.lock, the example\'s with .example before '
      '.lock', () {
    final LocksDirectory locks = .beside(.parse('/c/muster.yaml', .posix)!);
    final GitCodebase pinned = codebase(
      'app',
      'https://example.com/app.git',
      'a' * 40,
      '.',
      .dart,
    );
    final String key = LockKey.of(Git(pinned)).hex;
    expect(
      keptLockOf(locks, Git(pinned), .root).path,
      '/c/muster_locks/app-$key.lock',
    );
    expect(
      keptLockOf(locks, Git(pinned), .example).path,
      '/c/muster_locks/app-$key.example.lock',
    );
  });

  test('a kept lock beside a Windows manifest is joined in its '
      'separators', () {
    final LocksDirectory locks = .beside(
      .parse(r'C:\c\muster.yaml', .windows)!,
    );
    final GitCodebase pinned = codebase(
      'app',
      'https://example.com/app.git',
      'a' * 40,
      '.',
      .dart,
    );
    expect(
      keptLockOf(locks, Git(pinned), .example).path,
      r'C:\c\muster_locks\app-'
      '${LockKey.of(Git(pinned)).hex}.example.lock',
    );
  });
}

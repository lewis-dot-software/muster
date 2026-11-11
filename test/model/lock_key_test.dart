import 'dart:convert';

import 'package:muster/src/model/lock_key.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';

void main() {
  final String hash = 'ab' * 20;

  test('a kept lock\'s key is a SHA-256 in hexadecimal', () {
    expect(
      LockKey.of(codebase('app', '/srv/app.git', hash, '.', .dart)).hex,
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );
  });

  test('values that would run together give two keys', () {
    // Joined with nothing between them, a URL and commit of these lengths
    // read alike: `/srv/` and 64 `a`s.
    expect(
      LockKey.of(codebase('app', '/srv/${'a' * 24}', 'a' * 40, '.', .dart)),
      isNot(LockKey.of(codebase('app', '/srv/', 'a' * 64, '.', .dart))),
    );
  });

  test('values that would run together under a delimiter give two keys', () {
    final String c1 = 'ab' * 20;
    final String c2 = 'cd' * 20;
    for (final String d in ['\n', '|', ':', ' ', ',', '","']) {
      expect(
        LockKey.of(codebase('app', '/srv/u', c1, 'r$d$c2${d}z', .dart)),
        isNot(LockKey.of(codebase('app', '/srv/u$d$c1${d}r', c2, 'z', .dart))),
        reason: 'joined by ${jsonEncode(d)}',
      );
    }
  });

  test('each value the resolve turns on moves the key', () {
    final LockKey base = LockKey.of(
      codebase('app', '/srv/app.git', hash, '.', .dart),
    );
    for (final LockKey moved in [
      LockKey.of(codebase('app', '/srv/app2.git', hash, '.', .dart)),
      LockKey.of(codebase('app', '/srv/app.git', 'cd' * 20, '.', .dart)),
      LockKey.of(codebase('app', '/srv/app.git', hash, 'pkgs', .dart)),
      LockKey.of(codebase('app', '/srv/app.git', hash, '.', .flutter)),
    ]) {
      expect(moved, isNot(base));
    }
  });
}

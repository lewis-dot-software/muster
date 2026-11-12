import 'dart:convert';

import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/lock_key.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';

/// The git codebase of the parts given, as a [Codebase].
Codebase _git(
  String name,
  String url,
  String commit,
  String root,
  Toolchain toolchain,
) => Git(codebase(name, url, commit, root, toolchain));

void main() {
  final String hash = 'ab' * 20;

  test('a kept lock\'s key is a SHA-256 in hexadecimal', () {
    expect(
      LockKey.of(_git('app', '/srv/app.git', hash, '.', .dart)).hex,
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );
  });

  test('values that would run together give two keys', () {
    // Joined with nothing between them, a URL and commit of these lengths
    // read alike: `/srv/` and 64 `a`s.
    expect(
      LockKey.of(_git('app', '/srv/${'a' * 24}', 'a' * 40, '.', .dart)),
      isNot(LockKey.of(_git('app', '/srv/', 'a' * 64, '.', .dart))),
    );
  });

  test('values that would run together under a delimiter give two keys', () {
    final String c1 = 'ab' * 20;
    final String c2 = 'cd' * 20;
    for (final String d in ['\n', '|', ':', ' ', ',', '","']) {
      expect(
        LockKey.of(_git('app', '/srv/u', c1, 'r$d$c2${d}z', .dart)),
        isNot(LockKey.of(_git('app', '/srv/u$d$c1${d}r', c2, 'z', .dart))),
        reason: 'joined by ${jsonEncode(d)}',
      );
    }
  });

  test('each value the resolve turns on moves the key', () {
    final LockKey base = LockKey.of(
      _git('app', '/srv/app.git', hash, '.', .dart),
    );
    for (final LockKey moved in [
      LockKey.of(_git('app', '/srv/app2.git', hash, '.', .dart)),
      LockKey.of(_git('app', '/srv/app.git', 'cd' * 20, '.', .dart)),
      LockKey.of(_git('app', '/srv/app.git', hash, 'pkgs', .dart)),
      LockKey.of(_git('app', '/srv/app.git', hash, '.', .flutter)),
    ]) {
      expect(moved, isNot(base));
    }
  });

  test("each value a hosted codebase's resolve turns on moves its key, and "
      'its name does not', () {
    final LockKey base = LockKey.of(
      Hosted(hosted('app', 'args', '2.7.0', .alone, .dart)),
    );
    for (final LockKey moved in [
      LockKey.of(Hosted(hosted('app', 'path', '2.7.0', .alone, .dart))),
      LockKey.of(Hosted(hosted('app', 'args', '2.7.1', .alone, .dart))),
      LockKey.of(Hosted(hosted('app', 'args', '2.7.0', .asDependency, .dart))),
      LockKey.of(Hosted(hosted('app', 'args', '2.7.0', .alone, .flutter))),
    ]) {
      expect(moved, isNot(base));
    }
    expect(
      LockKey.of(Hosted(hosted('other', 'args', '2.7.0', .alone, .dart))),
      base,
    );
  });
}

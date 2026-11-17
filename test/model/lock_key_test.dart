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
    for (final String d in ['|', ':', ' ', ',', '","']) {
      expect(
        LockKey.of(_git('app', '/srv/u', c1, 'r$d$c2${d}z', .dart)),
        isNot(LockKey.of(_git('app', '/srv/u$d$c1${d}r', c2, 'z', .dart))),
        reason: 'joined by ${jsonEncode(d)}',
      );
    }
  });

  test('each value the resolve turns on moves the key', () {
    final LockKey base = .of(_git('app', '/srv/app.git', hash, '.', .dart));
    for (final LockKey moved in [
      .of(_git('app', '/srv/app2.git', hash, '.', .dart)),
      .of(_git('app', '/srv/app.git', 'cd' * 20, '.', .dart)),
      .of(_git('app', '/srv/app.git', hash, 'pkgs', .dart)),
      .of(_git('app', '/srv/app.git', hash, '.', .flutter)),
    ]) {
      expect(moved, isNot(base));
    }
  });

  // A consumer's kept locks are named by these keys, so a change that moves
  // one finds none of them and answers each load `Unlocked`. Each digest is
  // the SHA-256 of a JSON list written by hand, not by the code under test.
  test('a git codebase keeps the key its locks are named by since v0.1.0', () {
    for (final (Codebase git, String hex) in [
      (
        _git('app', 'https://example.com/app.git', hash, '.', .dart),
        'bd29bbb6b8915a90bd2fcc2cdf2a5d90f81117eec31e27db3492049a7def173f',
      ),
      (
        _git(
          'app',
          'git@example.com:org/app.git',
          '0123456789abcdef' * 4,
          'packages/app',
          .flutter,
        ),
        '9ec7eb69d89c83d97701680f9bfc9b7972c22be9eb89bfc3566979ea21123758',
      ),
      (
        // A `\` the JSON escapes, and a letter past ASCII it does not.
        _git('app', r'C:\srv\app.git', 'cd' * 20, 'pakete/café', .dart),
        '7b5dd454d9d05044ca25599edd0503c2307f8f277a0f2a4e9387e95818eca4cc',
      ),
    ]) {
      expect(LockKey.of(git).hex, hex);
    }
  });

  test('a hosted codebase keeps the key its locks are named by', () {
    for (final (Codebase package, String hex) in [
      (
        Hosted(hosted('app', 'args', '2.7.0', .alone, .dart)),
        '34ffe6696846bc8b79160c4df71ff6d674ac234bb5b28dc30f9a2875e6469db3',
      ),
      (
        Hosted(hosted('app', 'dio', '5.4.3+1', .asDependency, .flutter)),
        '93fdf185f3cbe90b29035f0f1e4cb4eaf298b2ad8a1f0cb643c6280c925db433',
      ),
    ]) {
      expect(LockKey.of(package).hex, hex);
    }
  });

  test("each value a hosted codebase's resolve turns on moves its key, and "
      'its name does not', () {
    final LockKey base = .of(
      Hosted(hosted('app', 'args', '2.7.0', .alone, .dart)),
    );
    for (final LockKey moved in [
      .of(Hosted(hosted('app', 'path', '2.7.0', .alone, .dart))),
      .of(Hosted(hosted('app', 'args', '2.7.1', .alone, .dart))),
      .of(Hosted(hosted('app', 'args', '2.7.0', .asDependency, .dart))),
      .of(Hosted(hosted('app', 'args', '2.7.0', .alone, .flutter))),
    ]) {
      expect(moved, isNot(base));
    }
    expect(
      LockKey.of(Hosted(hosted('other', 'args', '2.7.0', .alone, .dart))),
      base,
    );
  });
}

import 'dart:io';

import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/fetch_outcome.dart';
import 'package:muster/src/model/git_url.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/askpass.dart';
import '../support/asking_server.dart';
import '../support/faults.dart';
import '../support/git.dart';
import '../support/host.dart';
import '../support/quiet_in.dart';
import '../support/ssh_server.dart';

/// A pin the clone never reaches, since each clone here fails first.
final Commit _pin = .parse('0' * 40)!;

void main() {
  late Directory temp;
  late Askpass askpass;

  /// The test process's environment, quiet as [quietIn] makes it.
  late Map<String, String> quiet;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    askpass = await .make(temp);
    quiet = quietIn(temp);
  });

  tearDown(() => temp.delete(recursive: true));

  /// Sets [key] to [value] in the user's own git configuration.
  Future<void> configure(String key, String value) => Runner(quiet, host).run((
    executable: .git,
    arguments: ['config', '--file', gitConfigIn(temp), key, value],
  ));

  /// Expects the cache's clone of [url], its git run under [environment], to
  /// fail with git writing [message], no askpass of the caller's asked.
  Future<void> failsUnasked(
    GitUrl url,
    Map<String, String> environment,
    String message,
  ) async {
    await expectLater(
      cacheIn(temp, .new(environment, host)).clone(url, _pin),
      throwsA(
        storeFault(
          isA<CommandFailed>().having(
            (CommandFailed f) => f.stderr,
            'stderr',
            contains(message),
          ),
        ),
      ),
    );
    expect(await askpass.asked, isFalse, reason: 'the askpass was asked');
  }

  group('a clone of an SSH URL whose caller names an askpass for every '
      "prompt, git's and ssh's,", () {
    late SshServer server;
    late GitUrl url;

    setUp(() async {
      server = await .make(temp);
      url = server.url(p.join(temp.path, 'repo'));
    });

    /// The environment of a caller that names [askpass] for every prompt.
    Map<String, String> answering() => {
      ...quiet,
      'GIT_ASKPASS': askpass.path,
      'SSH_ASKPASS': askpass.path,
      'SSH_ASKPASS_REQUIRE': 'force',
    };

    test('to a host not yet known fails, never asking whether to trust '
        'it', () async {
      await configure(
        'core.sshCommand',
        server.command(locked: false, knownHost: false),
      );
      await failsUnasked(url, answering(), 'Host key verification failed.');
    });

    test('with a key whose passphrase is wanted fails, never asking for '
        'it', () async {
      await configure(
        'core.sshCommand',
        server.command(locked: true, knownHost: true),
      );
      await failsUnasked(url, answering(), 'Permission denied (publickey)');
    });
  });

  group('a clone of an HTTP URL whose credentials are wanted fails, never '
      'asking for them', () {
    late AskingServer server;

    setUp(() async => server = await .start());

    tearDown(() => server.close());

    test('where its caller names an askpass in GIT_ASKPASS', () async {
      await failsUnasked(server.url, {
        ...quiet,
        'GIT_ASKPASS': askpass.path,
      }, 'could not read Username');
    });

    test('where its caller names an askpass in core.askPass', () async {
      await configure('core.askPass', askpass.path);
      await failsUnasked(server.url, quiet, 'could not read Username');
    });

    test('where its caller names an askpass in SSH_ASKPASS', () async {
      await failsUnasked(server.url, {
        ...quiet,
        'SSH_ASKPASS': askpass.path,
      }, 'could not read Username');
    });
  });
}

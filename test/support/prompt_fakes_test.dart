import 'dart:io';

import 'package:muster/src/model/git_url.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'askpass.dart';
import 'asking_server.dart';
import 'quiet_in.dart';
import 'ssh_server.dart';

void main() {
  late Directory temp;
  late Askpass askpass;
  late Map<String, String> quiet;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    askpass = await .make(temp);
    quiet = quietIn(temp);
  });

  tearDown(() => temp.delete(recursive: true));

  /// Git's clone of [url] into the test's directory, run straight from the
  /// test with none of muster's guards, under [environment], its
  /// `core.sshCommand` [ssh] where one is given.
  Future<ProcessResult> cloneBare(
    GitUrl url,
    Map<String, String> environment, [
    String? ssh,
  ]) => Process.run(
    'git',
    [
      if (ssh != null) ...['-c', 'core.sshCommand=$ssh'],
      'clone',
      '--quiet',
      '--bare',
      url.url,
      p.join(temp.path, 'clone'),
    ],
    environment: environment,
    includeParentEnvironment: false,
  );

  test('the askpass records a prompt for credentials git puts to it, and '
      'answers none', () async {
    final AskingServer server = await .start();
    addTearDown(server.close);
    final ProcessResult cloned = await cloneBare(server.url, {
      ...quiet,
      'GIT_ASKPASS': askpass.path,
    });
    expect(cloned.exitCode, isNot(0));
    expect(await askpass.asked, isTrue);
  });

  group('over the SSH server, with ssh told to put every question to the '
      'askpass,', () {
    late SshServer server;
    late GitUrl url;

    setUp(() async {
      server = await .make(temp);
      url = server.url(p.join(temp.path, 'repo'));
    });

    Map<String, String> answering() => {
      ...quiet,
      'SSH_ASKPASS': askpass.path,
      'SSH_ASKPASS_REQUIRE': 'force',
    };

    test('the askpass records whether to trust a host not yet known', () async {
      await cloneBare(
        url,
        answering(),
        server.command(locked: false, knownHost: false),
      );
      expect(await askpass.asked, isTrue);
    });

    test('the askpass records a passphrase wanted for a key', () async {
      await cloneBare(
        url,
        answering(),
        server.command(locked: true, knownHost: true),
      );
      expect(await askpass.asked, isTrue);
    });

    test('the server accepts the key that wants no passphrase, from a host '
        'it trusts, asking nothing', () async {
      final ProcessResult reached = await Process.run(
        'sh',
        [
          '-c',
          '${server.command(locked: false, knownHost: true)} -v '
              '${server.destination} true',
        ],
        environment: answering(),
        includeParentEnvironment: false,
      );
      expect(
        reached.stderr,
        contains('Authenticated to muster.invalid'),
        reason: 'the server refused the key',
      );
      expect(await askpass.asked, isFalse);
    });
  });
}

import 'dart:io';

import 'package:muster/src/model/git_url.dart';
import 'package:path/path.dart' as p;

import 'shell_quoted.dart';

/// An sshd a test's ssh starts as its proxy command, serving one connection
/// per run as the user the test runs as, with its keys and configuration in a
/// directory of its own.
class SshServer {
  SshServer._(this._directory, this._sshd, this._user);

  /// The server made in `ssh` under [parent], its keys made by ssh-keygen.
  ///
  /// Throws a [StateError] where no `sshd` stands in `/usr/sbin` or on the
  /// test process's `PATH`, since the server needs one.
  static Future<SshServer> make(Directory parent) async {
    final Directory directory = await .new(p.join(parent.path, 'ssh')).create();
    String at(String name) => p.join(directory.path, name);
    for (final (String name, String passphrase) in [
      ('host', ''),
      ('open', ''),
      ('locked', 'muster'),
    ]) {
      await _ran('ssh-keygen', [
        '-q',
        '-t',
        'ed25519',
        '-N',
        passphrase,
        '-f',
        at(name),
      ]);
    }
    await File(at('authorized_keys')).writeAsString(
      '${await File(at('open.pub')).readAsString()}'
      '${await File(at('locked.pub')).readAsString()}',
    );
    final String hostKey = (await File(
      at('host.pub'),
    ).readAsString()).split(' ').take(2).join(' ');
    await File(at('known_hosts')).writeAsString('$_host $hostKey\n');
    await File(at('unknown_hosts')).create();
    await File(at('sshd_config')).writeAsString(
      'HostKey ${at('host')}\n'
      'AuthorizedKeysFile ${at('authorized_keys')}\n'
      'AuthenticationMethods publickey\n'
      'StrictModes no\n'
      'PidFile none\n'
      // An sshd that can read the user's shadow entry, as root can its own
      // and any user can one the system serves to all, refuses an account
      // whose password is locked, unless PAM takes the account's check.
      'UsePAM yes\n',
    );
    return ._(directory, _sshdPath(), (await _ran('id', ['-un'])).trim());
  }

  final Directory _directory;
  final String _sshd;
  final String _user;

  /// The user and host ssh is given to reach the server.
  String get destination => '$_user@$_host';

  /// The URL on the server of the repo at the absolute path [repo].
  GitUrl url(String repo) => .parse('ssh://$destination$repo')!;

  /// The `core.sshCommand` that reaches the server with no agent and no
  /// configuration of the user's, offering a key whose passphrase is asked
  /// for where [locked], and trusting the server's host key where
  /// [knownHost].
  String command({required bool locked, required bool knownHost}) {
    String at(String name) => p.join(_directory.path, name);
    return [
      'ssh',
      '-F',
      '/dev/null',
      '-o',
      shellQuoted('ProxyCommand=$_sshd -i -f ${at('sshd_config')}'),
      '-o',
      shellQuoted(
        'UserKnownHostsFile=${at(knownHost ? 'known_hosts' : 'unknown_hosts')}',
      ),
      '-o',
      'GlobalKnownHostsFile=/dev/null',
      '-o',
      'StrictHostKeyChecking=ask',
      '-o',
      'IdentityAgent=none',
      '-o',
      'IdentitiesOnly=yes',
      '-i',
      shellQuoted(at(locked ? 'locked' : 'open')),
    ].join(' ');
  }
}

/// The host name the server answers to, which no resolver knows, so nothing
/// but the proxy command reaches it.
const String _host = 'muster.invalid';

/// The absolute path of an `sshd`, which it needs to start.
String _sshdPath() {
  for (final String directory in [
    '/usr/sbin',
    ...?Platform.environment['PATH']?.split(':'),
  ]) {
    final String sshd = p.join(directory, 'sshd');
    if (File(sshd).existsSync()) {
      return p.absolute(sshd);
    }
  }
  throw StateError('the ssh tests need an sshd, in /usr/sbin or on PATH');
}

/// What [executable] wrote, run with [arguments] to an exit of 0.
///
/// Throws a [ProcessException] where it exits with any other code.
Future<String> _ran(String executable, List<String> arguments) async {
  final ProcessResult result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stderr}',
      result.exitCode,
    );
  }
  return result.stdout as String;
}

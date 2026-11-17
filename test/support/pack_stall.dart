import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'chmod.dart';
import 'shell_quoted.dart';

/// A hook git's upload-pack runs in place of its pack-objects, named by a
/// git configuration of its own, which sends the pack's first [_sent] bytes
/// and stalls there, the clone's git still running, until its test lets it
/// go, then fails the pack.
///
/// [_sent] is more than the pipes between the hook and the clone's
/// index-pack hold, so once the hook stalls the clone has read part of the
/// pack and written it into its temporary clone.
class PackStall {
  PackStall._(this.config, this._stalled, this._go, this._pack);

  /// The hook made under [parent], with its configuration and the pipes it
  /// stalls on beside it.
  static Future<PackStall> make(Directory parent) async {
    String at(String name) => p.join(parent.path, 'stall-$name');
    final String stalled = at('stalled');
    final String go = at('go');
    final ProcessResult made = await Process.run('mkfifo', [stalled, go]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final String pack = shellQuoted(at('pack'));
    final File hook = await File(at('hook')).writeAsString(
      '#!/bin/sh\n'
      '"\$@" > $pack\n'
      'head -c $_sent $pack\n'
      ': > ${shellQuoted(stalled)}\n'
      'cat ${shellQuoted(go)} > /dev/null\n'
      'exit 1\n',
    );
    await chmod('+x', hook);
    final File config = await File(at('gitconfig')).writeAsString(
      '[uploadpack]\n\tpackObjectsHook = ${shellQuoted(hook.path)}\n',
    );
    return ._(config.path, stalled, go, at('pack'));
  }

  /// Contents for a file of a commit, which pack to more than the hook
  /// sends, so a clone of the commit stalls with its pack part written.
  static final String outsized = () {
    final Random random = .new(0);
    return base64Encode([
      for (int i = 0; i < 2 * _sent; i++) random.nextInt(256),
    ]);
  }();

  /// The bytes of the pack the hook sends before it stalls.
  static const int _sent = 1 << 20;

  /// The path of the git configuration naming the hook, for the git of a
  /// clone that stalls to read as the user's own, as `GIT_CONFIG_GLOBAL`,
  /// since git clears the configuration its environment carries before it
  /// starts upload-pack on a path.
  final String config;

  final String _stalled;

  final String _go;

  /// The path of the whole pack, which the hook writes before it sends any.
  final String _pack;

  bool _held = false;

  /// The bytes of the whole pack, once the hook has stalled.
  Future<int> packed() => File(_pack).length();

  /// Waits until the hook has sent what it sends and stalls.
  Future<void> stalled() async {
    await File(_stalled).readAsString();
    _held = true;
  }

  /// Lets the hook go where it stalls, which fails the pack.
  Future<void> release() async {
    if (_held) {
      _held = false;
      await File(_go).writeAsString('');
    }
  }
}

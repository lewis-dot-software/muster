import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'chmod.dart';
import 'git_ends.dart';
import 'shell_quoted.dart';

/// A hook git's upload-pack runs in place of its pack-objects, named by a
/// git configuration of its own, which sends the pack's first [_sent] bytes
/// and stalls there, the clone's git still running, until its test lets it
/// go, then fails the pack or sends the rest of it.
///
/// [_sent] is more than the pipes between the hook and the clone's
/// index-pack hold, so once the hook stalls the clone has read part of the
/// pack and written it into its temporary clone.
class PackStall {
  PackStall._(this.config, this._stalled, this._go, this._pack, this._ends);

  /// The hook named [name] made under [parent], with its configuration and
  /// the pipes it stalls on and git's trace goes to beside it.
  static Future<PackStall> make(
    Directory parent, [
    String name = 'stall',
  ]) async {
    String at(String part) => p.join(parent.path, '$name-$part');
    final String stalled = at('stalled');
    final String go = at('go');
    final String trace = at('trace');
    final ProcessResult made = await Process.run('mkfifo', [
      stalled,
      go,
      trace,
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final String pack = shellQuoted(at('pack'));
    final File hook = await File(at('hook')).writeAsString(
      '#!/bin/sh\n'
      '"\$@" > $pack\n'
      'head -c $_sent $pack\n'
      'printf %s "\$GIT_TRACE2_PARENT_SID" > ${shellQuoted(stalled)}\n'
      'read word < ${shellQuoted(go)}\n'
      '[ "\$word" = ${_Word.send.name} ] || exit 1\n'
      'tail -c +${_sent + 1} $pack\n',
    );
    await chmod('+x', hook);
    final File config = await File(at('gitconfig')).writeAsString(
      '[uploadpack]\n'
      '\tpackObjectsHook = ${shellQuoted(hook.path)}\n'
      '[trace2]\n'
      '\teventTarget = ${_configQuoted(trace)}\n',
    );
    return ._(config.path, stalled, go, at('pack'), await .open(trace));
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

  /// The path of the git configuration naming the hook, and a trace of each
  /// git it reaches, for the git of a clone that stalls to read as the
  /// user's own, as `GIT_CONFIG_GLOBAL`, since git clears the configuration
  /// its environment carries before it starts upload-pack on a path.
  final String config;

  final String _stalled;

  final String _go;

  /// The path of the whole pack, which the hook writes before it sends any.
  final String _pack;

  final GitEnds _ends;

  /// The trace2 session id of the clone's git, while the hook stalls.
  String? _clone;

  /// The bytes of the whole pack, once the hook has stalled.
  Future<int> packed() => File(_pack).length();

  /// Waits until the hook has sent what it sends and stalls.
  Future<void> stalled() async {
    // The hook's parent is upload-pack, whose own parent is the clone's git.
    final String parent = await File(_stalled).readAsString();
    _clone = parent.substring(0, parent.lastIndexOf('/'));
  }

  /// Lets the hook go where it stalls, sending the rest of the pack, so the
  /// clone's git goes on to finish the clone.
  Future<void> finish() async {
    if (_clone != null) {
      _clone = null;
      await File(_go).writeAsString('${_Word.send.name}\n');
    }
  }

  /// Lets the hook go where it stalls, which fails the pack, and waits until
  /// the clone's git has ended, what it removes as it ends removed, then
  /// until every git the configuration reached has.
  Future<void> release() async {
    if (_clone case final String clone) {
      _clone = null;
      await File(_go).writeAsString('${_Word.fail.name}\n');
      await _ends.ended(clone);
    }
    await _ends.close();
  }
}

/// What the hook is told to do with the rest of the pack.
enum _Word { send, fail }

/// [text] as one value of a git configuration, whatever it holds.
String _configQuoted(String text) =>
    '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

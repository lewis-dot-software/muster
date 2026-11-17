import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:muster/src/model/command.dart';

import 'act.dart';
import 'apart.dart';
import 'contention.dart';
import 'keeping.dart';
import 'pause.dart';
import 'said.dart';
import 'support_program.dart';
import 'take.dart';
import 'told.dart';
import 'word.dart';

/// A load, a claim held bare, a claim taken and tried once more, or claims
/// never released and tried once they are collected, run apart from its test
/// as an isolate or a process, which tells the test each step and waits on
/// its word.
class Contender {
  Contender._(this._tell, this._kill, Future<void> exited) {
    _exited = exited.then(
      (_) {
        _over = true;
        _settle(_failure ?? StateError('the contender ended'));
      },
      onError: (Object error) {
        _over = true;
        _fail(error);
      },
    );
  }

  /// A contender [apart] holding the claim on the checkout [name] under the
  /// consumer's [root].
  static Future<Contender> holding(Apart apart, String root, String name) =>
      _start(apart, {
        'contention': Contention.hold.name,
        'root': root,
        'name': name,
      });

  /// A contender in a process of its own taking the claim on the checkout
  /// [name] under the consumer's [root] by [take], for an act that does
  /// [act], then trying it once more, which an isolate could not, since a
  /// process another test file starts would carry the claim until its exec.
  static Future<Contender> reletting(
    String root,
    String name,
    Take take,
    Act act,
  ) => _start(.process, {
    'contention': Contention.relet.name,
    'root': root,
    'name': name,
    'take': take.name,
    'act': act.name,
  });

  /// A contender in a process of its own taking the claim on each checkout
  /// of [names] under the consumer's [root] for an act that never ends,
  /// keeping what [keeping] names of each and never releasing it, then
  /// trying each once its hold is collected, which an isolate could not,
  /// since a process another test file starts would carry the claims until
  /// its exec.
  static Future<Contender> abandoning(
    String root,
    List<String> names,
    Keeping keeping,
  ) => _start(.process, {
    'contention': Contention.abandon.name,
    'root': root,
    'names': names,
    'keeping': keeping.name,
  });

  /// A contender [apart] loading [manifests] with its root at [root], reading
  /// [variables], its load holding the command [pause] names where one is
  /// given.
  static Future<Contender> loading(
    Apart apart, {
    required String root,
    required Map<String, String> variables,
    required List<String> manifests,
    Pause? pause,
  }) => _start(apart, {
    'contention': Contention.load.name,
    'root': root,
    'variables': variables,
    'manifests': manifests,
    'pause': pause?.name,
  });

  static Future<Contender> _start(
    Apart apart,
    Map<String, Object?> brief,
  ) async {
    switch (apart) {
      case .isolate:
        final String program = await SupportProgram.contender.kernel();
        final ReceivePort said = .new();
        final ReceivePort exit = .new();
        final ReceivePort errors = .new();
        final Isolate isolate = await .spawnUri(
          .file(program),
          [jsonEncode(brief)],
          said.sendPort,
          packageConfig: await Isolate.packageConfig,
          onExit: exit.sendPort,
          onError: errors.sendPort,
        );
        final Completer<SendPort> words = .new();
        late final Contender contender;
        contender = ._(
          (Word word) async => (await words.future).send(word.name),
          () async => isolate.kill(priority: Isolate.immediate),
          exit.first.then((_) {
            said.close();
            errors.close();
          }),
        );
        said.listen((Object? message) {
          if (message is SendPort) {
            words.complete(message);
          } else {
            contender._hear(message as String);
          }
        });
        errors.listen(
          (Object? error) =>
              contender._fail(StateError('the contender threw $error')),
        );
        return contender;
      case .process:
        final Process process = await .start(
          Platform.resolvedExecutable,
          await SupportProgram.contender.started([jsonEncode(brief)]),
        );
        final StringBuffer stderr = .new();
        process.stderr.transform(utf8.decoder).listen(stderr.write);
        final Contender contender = ._(
          (Word word) async => process.stdin.writeln(word.name),
          () async => process.kill(.sigkill),
          process.exitCode.then((int code) {
            if (code != 0 && code != -ProcessSignal.sigkill.signalNumber) {
              throw StateError('the contender exited $code: $stderr');
            }
          }),
        );
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(contender._hear);
        return contender;
    }
  }

  final Future<void> Function(Word word) _tell;
  final Future<void> Function() _kill;
  late final Future<void> _exited;

  /// Everything the contender has said, in order.
  final List<String> said = [];

  final List<(bool Function(String said), Completer<String>)> _waits = [];

  /// What the contender failed with, where it failed: an exit other than
  /// its own or a kill's, or an error its isolate threw.
  Object? _failure;

  /// Whether the contender has ended.
  bool _over = false;

  /// Every command the contender has run so far, in order.
  List<Command> get ran => [
    for (final String line in said)
      if (_after(line, .ran) case final String json)
        _command(jsonDecode(json) as List<Object?>),
  ];

  /// The first thing said that [where] holds of, waited on where nothing yet
  /// has.
  Future<String> until(bool Function(String said) where) {
    for (final String line in said) {
      if (where(line)) {
        return .value(line);
      }
    }
    if (_failure case final Object failure) {
      return .error(failure);
    }
    if (_over) {
      return .error(StateError('the contender ended'));
    }
    final Completer<String> wait = .new();
    _waits.add((where, wait));
    return wait.future;
  }

  /// The script the contender was started from, once it has said.
  Future<Uri> script() async => .parse(
    _after(
      await until((String line) => _after(line, .script) != null),
      .script,
    )!,
  );

  /// Waits until the contender says [word] alone.
  Future<void> told(Said word) => until((String line) => line == word.name);

  /// Whether its claim, let go, was taken again where it was tried once
  /// more, once it has said.
  Future<bool> letGo() async =>
      await until(
        (String line) => line == Said.free.name || line == Said.kept.name,
      ) ==
      Said.free.name;

  /// Whether each claim it never released was free, in order, where it was
  /// tried once its hold was collected, once it has said.
  Future<List<bool>> tried() async {
    final String line = await until(
      (String line) => _after(line, .tried) != null,
    );
    return [
      for (final Object? free
          in jsonDecode(_after(line, .tried)!) as List<Object?>)
        free! as bool,
    ];
  }

  /// Each codebase's outcome, once the load is done.
  Future<Map<String, Told>> done() async {
    final String line = await until(
      (String line) => _after(line, .done) != null,
    );
    return {
      for (final MapEntry<String, Object?>(:key, :value)
          in (jsonDecode(_after(line, .done)!) as Map<String, Object?>).entries)
        key: switch (value) {
          {'case': final String outcome, 'path': final String? path} => (
            outcome: .values.byName(outcome),
            path: path,
          ),
          _ => throw StateError('a refused load: $value'),
        },
    };
  }

  /// Tells the contender [word].
  Future<void> tell(Word word) => _tell(word);

  /// Kills the contender, and waits until it has ended.
  ///
  /// Throws what the contender failed with, where it failed before the kill.
  Future<void> kill() async {
    await _kill();
    await _ended();
  }

  /// Tells the contender to end, where it has not already, and waits until
  /// it has.
  ///
  /// Throws what the contender failed with, where it failed.
  Future<void> end() async {
    if (!_over) {
      await tell(.exit);
    }
    await _ended();
  }

  Future<void> _ended() async {
    await _exited;
    if (_failure case final Object failure) {
      throw failure;
    }
  }

  void _hear(String line) {
    said.add(line);
    for (final (bool Function(String) where, Completer<String> wait) in List.of(
      _waits,
    )) {
      if (where(line)) {
        _waits.remove((where, wait));
        wait.complete(line);
      }
    }
  }

  void _fail(Object failure) {
    _failure ??= failure;
    _settle(failure);
  }

  /// Fails every wait not yet met with [reason].
  void _settle(Object reason) {
    for (final (_, Completer<String> wait) in _waits) {
      wait.completeError(reason);
    }
    _waits.clear();
  }
}

/// Whether [line] said is [said] followed by its detail, and that detail.
String? _after(String line, Said said) => line.startsWith('${said.name} ')
    ? line.substring(said.name.length + 1)
    : null;

/// The command [parts] spell: its executable's name, then its arguments.
Command _command(List<Object?> parts) => (
  executable: .values.byName(parts.first! as String),
  arguments: [for (final Object? part in parts.skip(1)) part! as String],
);

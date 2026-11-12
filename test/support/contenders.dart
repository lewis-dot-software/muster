import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:muster/src/model/command.dart';
import 'package:muster/src/model/executable.dart';
import 'package:path/path.dart' as p;

import 'contention.dart';
import 'pause.dart';
import 'loads.dart';

/// Where a contender runs apart from its test.
enum Apart {
  /// An isolate of the test's process, in a group of its own, as `dart test`
  /// runs each test file.
  isolate,

  /// A process of its own, as `flutter test` runs each test file.
  process,
}

/// One codebase's outcome as a contender tells it: its case's name, and the
/// path of the package it hands out where it is fetched.
typedef Told = ({String outcome, String? path});

/// A load, or a claim held bare, run apart from its test as an isolate or a
/// process, which tells the test each step and waits on its word.
class Contender {
  Contender._(this._tell, this._kill, Future<void> exited) {
    _exited = exited.then(
      (_) => _fail('the contender ended'),
      onError: (Object error) => _fail(error),
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
    final String program = p.join(
      await musterRoot(),
      'test',
      'support',
      'contender.dart',
    );
    switch (apart) {
      case .isolate:
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
        errors.listen((Object? error) => contender._fail('$error'));
        return contender;
      case .process:
        final Process
        process = await Process.start(Platform.resolvedExecutable, [
          '--packages=${p.join(await musterRoot(), '.dart_tool', 'package_config.json')}',
          program,
          jsonEncode(brief),
        ]);
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

  Object? _failure;

  /// Every command the contender has run so far, in order.
  List<Command> get ran => [
    for (final String line in said)
      if (_after(line, Said.ran) case final String json)
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
    final Completer<String> wait = .new();
    _waits.add((where, wait));
    return wait.future;
  }

  /// Waits until the contender says [word] alone.
  Future<void> told(Said word) => until((String line) => line == word.name);

  /// Each codebase's outcome, once the load is done.
  Future<Map<String, Told>> done() async {
    final String line = await until(
      (String line) => _after(line, Said.done) != null,
    );
    return {
      for (final MapEntry<String, Object?>(:key, :value) in (jsonDecode(
        _after(line, Said.done)!,
      ) as Map<String, Object?>).entries)
        key: switch (value) {
          {'case': final String outcome, 'path': final String? path} => (
            outcome: outcome,
            path: path,
          ),
          _ => throw StateError('a refused load: $value'),
        },
    };
  }

  /// Tells the contender [word].
  Future<void> tell(Word word) => _tell(word);

  /// Kills the contender, and waits until it has ended.
  Future<void> kill() async {
    await _kill();
    await _exited;
  }

  /// Tells the contender to end, and waits until it has.
  Future<void> end() async {
    await tell(.exit);
    await _exited;
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
    for (final (_, Completer<String> wait) in _waits) {
      wait.completeError(failure);
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
  executable: Executable.values.byName(parts.first! as String),
  arguments: [for (final Object? part in parts.skip(1)) part! as String],
);

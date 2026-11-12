// A load, a claim held bare, or a claim taken and tried once more, run apart
// from the test that starts it, as an isolate or a process, telling the test
// each step it takes and waiting on the test's word where the test says to
// pause. Started by `Contender` alone.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:muster/muster.dart';
import 'package:muster/src/load/loader.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/store/claims.dart';
import 'package:muster/src/store/store_fault.dart';

import 'contention.dart';
import 'pause.dart';
import 'spy_runner.dart';

Future<void> main(List<String> arguments, [SendPort? port]) async {
  final _Line line = port == null ? _ProcessLine() : _IsolateLine(port);
  final Map<String, Object?> brief =
      jsonDecode(arguments.single) as Map<String, Object?>;
  final String root = brief['root'] as String;
  switch (Contention.values.byName(brief['contention'] as String)) {
    case .hold:
      final CheckoutPath checkout = .of(
        .new(root, .posix),
        .parse(brief['name'] as String)!,
      );
      await Claims(.posix).holding(checkout.claim, () async {
        line.say(Said.held.name);
        await line.heard(.release);
      });
    case .relet:
      final CheckoutPath checkout = .of(
        .new(root, .posix),
        .parse(brief['name'] as String)!,
      );
      final Claims claims = .new(
        .posix,
        () async => throw StateError('a claim no one holds was waited on'),
      );
      final Act act = .values.byName(brief['act'] as String);
      Future<void> acted() async => switch (act) {
        .returns => null,
        .throws => throw const FormatException('thrown by its brief'),
      };
      try {
        switch (Take.values.byName(brief['take'] as String)) {
          case .waiting:
            await claims.holding(checkout.claim, acted);
          case .once:
            if (!await claims.holdingIfFree(checkout.claim, acted)) {
              throw StateError('a claim no one holds was passed by');
            }
        }
      } on FormatException {
        // The throw its brief asked of its act, which its test asserts
        // passes through in a take of its own.
        if (act != .throws) {
          rethrow;
        }
      }
      line.say(
        await claims.holdingIfFree(checkout.claim, () async {})
            ? Said.free.name
            : Said.kept.name,
      );
    case .load:
      final Map<String, String> variables = {
        for (final MapEntry<String, Object?>(:String key, :Object? value)
            in (brief['variables'] as Map<String, Object?>).entries)
          key: value as String,
      };
      bool waited = false;
      final Load load = await Loader(
        (variables: variables, os: .posix),
        .new(root, .posix),
        _gated(variables, line, switch (brief['pause'] as String?) {
          final String pause => Pause.values.byName(pause),
          null => null,
        }),
        .new(.posix, () async {
          if (!waited) {
            waited = true;
            line.say(Said.waiting.name);
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }),
        .new(Directory.systemTemp.path, .posix),
      ).load(named: [for (final Object? m in brief['manifests'] as List) '$m']);
      line.say('${Said.done.name} ${jsonEncode(_outcomes(load))}');
  }
  await line.heard(.exit);
  await line.close();
}

/// Each codebase's outcome, by its name: its case's name, and the path of
/// the package it hands out where it is fetched.
Map<String, Object?> _outcomes(Load load) => switch (load) {
  Refused(:final LoadRefusal reason) => {'refused': '$reason'},
  Loaded(:final Map<CodebaseName, FetchOutcome> outcomes) => {
    for (final MapEntry<CodebaseName, FetchOutcome>(:key, :value)
        in outcomes.entries)
      key.name: switch (value) {
        Fetched(:final PackagePath package) => {
          'case': 'Fetched',
          'path': package.path,
        },
        FetchFailure() => {'case': '${value.runtimeType}', 'path': null},
      },
  },
};

/// A runner that tells the test each command before it runs it, and holds
/// the first command [pause] names until the test says to go on, or to fail
/// it as a command that exited 1.
SpyRunner _gated(Map<String, String> variables, _Line line, Pause? pause) {
  final SpyRunner runner = .new(variables);
  runner.before = (Command command) async {
    line.say(
      '${Said.ran.name} '
      '${jsonEncode([command.executable.name, ...command.arguments])}',
    );
    if (pause case final Pause held when held.holds(command)) {
      pause = null;
      line.say(Said.paused.name);
      switch (await line.heard(.go, .fail)) {
        case .go:
          break;
        case .fail:
          throw StoreFault(CommandFailed(command, 1, '', 'failed by its test'));
        case .release || .exit:
          throw StateError('a paused command hears only go or fail');
      }
    }
  };
  return runner;
}

/// The contender's line to its test: what it says, and the words it hears.
sealed class _Line {
  _Line(Stream<String> words) : _words = StreamIterator(words);

  final StreamIterator<String> _words;

  void say(String said);

  /// The next word heard, which must be one of [expected].
  Future<Word> heard(Word expected, [Word? or]) async {
    if (!await _words.moveNext()) {
      throw StateError('the test closed the line');
    }
    final Word word = Word.values.byName(_words.current);
    if (word != expected && word != or) {
      throw StateError('heard $word, expecting $expected');
    }
    return word;
  }

  Future<void> close();
}

final class _IsolateLine extends _Line {
  factory _IsolateLine(SendPort port) {
    final ReceivePort words = .new();
    port.send(words.sendPort);
    return ._(port, words);
  }

  _IsolateLine._(this._port, this._receive) : super(_receive.cast<String>());

  final SendPort _port;
  final ReceivePort _receive;

  @override
  void say(String said) => _port.send(said);

  @override
  Future<void> close() async => _receive.close();
}

final class _ProcessLine extends _Line {
  _ProcessLine()
    : super(stdin.transform(utf8.decoder).transform(const LineSplitter()));

  @override
  void say(String said) => stdout.writeln(said);

  @override
  Future<void> close() async {
    await stdout.flush();
    exit(0);
  }
}

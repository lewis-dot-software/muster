import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The git processes that have ended, by trace2 session id, read from the
/// events git writes to a fifo named as its `trace2.eventTarget`.
///
/// A process's `atexit` event, or its `signal` event where a signal ends it,
/// is the last it writes, after every handler of its own exit has run, a
/// clone's removal of what it made among them. An event longer than the
/// fifo writes whole, as a long command's `start` can be, may interleave
/// with another process's, so each line is searched for an end, never
/// parsed whole.
class GitEnds {
  GitEnds._(String fifo) {
    _read = File(fifo)
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach(_hear)
        .whenComplete(() {
          for (final MapEntry<String, Completer<void>>(:key, :value)
              in _waits.entries) {
            value.completeError(StateError('the trace ended before $key'));
          }
          _waits.clear();
        });
  }

  /// The ends read from [fifo], read until [close], a write end held open
  /// meanwhile so the read never ends between one git and the next.
  static Future<GitEnds> open(String fifo) async {
    final GitEnds ends = ._(fifo);
    ends._writer = await File(fifo).open(mode: .writeOnly);
    return ends;
  }

  late final Future<void> _read;

  late final RandomAccessFile _writer;

  final Set<String> _ended = {};

  final Map<String, Completer<void>> _waits = {};

  /// Waits until the process of the session [sid] has ended.
  Future<void> ended(String sid) =>
      _ended.contains(sid) ? .value() : (_waits[sid] ??= .new()).future;

  /// Lets the write end go, where it has not already, and waits until every
  /// git writing has ended.
  Future<void> close() => _closed ??= () async {
    await _writer.close();
    await _read;
  }();

  Future<void>? _closed;

  void _hear(String line) {
    for (final RegExpMatch end in _end.allMatches(line)) {
      final String sid = end[1]!;
      _ended.add(sid);
      _waits.remove(sid)?.complete();
    }
  }
}

/// The opening of the event that ends a process, and its session id.
final RegExp _end = .new(r'\{"event":"(?:atexit|signal)","sid":"([^"]+)"');

import 'package:glados/glados.dart';

/// The shrinks each generator of a property whose tries touch the disk or
/// run a process offers at most, so a failure ends after a bounded count of
/// tries, however long each try runs.
const int gitTries = 20;

/// A bound on how far glados shrinks a draw that fails.
extension ShrinkingAtMost<T> on Generator<T> {
  /// The generator, every value it draws offering [tries] shrinks at most,
  /// counted across the whole of its shrinking.
  Generator<T> shrinkingAtMost(int tries) =>
      (Random random, int size) => _Bounded(this(random, size), _Budget(tries));
}

/// What a draw has left of its shrinks.
final class _Budget {
  _Budget(this.left);

  int left;
}

/// A shrinkable whose shrinks, and theirs, each spend one of [_budget].
final class _Bounded<T> implements Shrinkable<T> {
  _Bounded(this._inner, this._budget);

  final Shrinkable<T> _inner;

  final _Budget _budget;

  @override
  T get value => _inner.value;

  @override
  Iterable<Shrinkable<T>> shrink() sync* {
    for (final Shrinkable<T> shrunk in _inner.shrink()) {
      if (_budget.left == 0) {
        return;
      }
      _budget.left--;
      yield _Bounded(shrunk, _budget);
    }
  }
}

import 'fetch_outcome.dart';

/// What a scratch's move to a commit gave: the scratch at the commit, or why
/// it could not be moved there.
sealed class Move {
  const Move();
}

/// A scratch at the commit it was moved to, holding that commit's tracked
/// files alone.
final class Moved extends Move {
  /// The move that brought the scratch to its commit.
  const Moved();
}

/// A move that failed, the scratch left wherever the failure left it.
final class MoveFailed extends Move {
  /// The move that failed for [failure].
  const MoveFailed(this.failure);

  /// Why the scratch could not be moved.
  final ActFailure failure;
}

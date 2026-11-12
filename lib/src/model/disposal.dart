import 'fetch_outcome.dart';

/// What a scratch's disposal gave: the scratch gone, or why it could not be
/// removed.
sealed class Disposal {
  const Disposal();
}

/// A scratch gone, its directory and its clone's record of it both.
final class Disposed extends Disposal {
  /// The disposal that removed the scratch.
  const Disposed();
}

/// A disposal that failed, part of the scratch perhaps still there.
final class DisposalFailed extends Disposal {
  /// The disposal that failed for [failure].
  const DisposalFailed(this.failure);

  /// Why the scratch could not be removed.
  final ActFailure failure;
}

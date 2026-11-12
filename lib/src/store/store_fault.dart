import '../model/fetch_outcome.dart';

/// An expected failure of the store's, thrown inside muster and carried out
/// of it as its [failure].
final class StoreFault implements Exception {
  /// The fault that carries [failure].
  const StoreFault(this.failure);

  /// Why the store's act failed.
  final FetchFailure failure;

  /// [failure] as the failure of an act on the world.
  ///
  /// Throws a [StateError] where [failure] is [Unlocked], which is no act's.
  ActFailure get act => switch (failure) {
    final ActFailure act => act,
    Unlocked() => throw StateError('$failure is no act on the world'),
  };

  /// [failure] as the [StoreFailed] a file act fails with.
  ///
  /// Throws a [StateError] where [failure] is any other, which no file act
  /// gives.
  StoreFailed get fileFailure => switch (failure) {
    final StoreFailed failed => failed,
    Unlocked() ||
    CommandFailed() ||
    Unstartable() ||
    PinMissing() => throw StateError('$failure is no file act\'s'),
  };
}

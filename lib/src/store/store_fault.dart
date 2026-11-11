import '../model/fetch_outcome.dart';

/// An expected failure of the store's, thrown inside muster and carried out
/// of it as its [failure].
final class StoreFault implements Exception {
  /// The fault that carries [failure].
  const StoreFault(this.failure);

  /// Why the store's act failed.
  final FetchFailure failure;
}

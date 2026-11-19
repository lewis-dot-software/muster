import '../model/load_refusal.dart';

/// A run refused for [reason] before any process or file write.
final class Refusal implements Exception {
  /// The refusal of a run for [reason].
  const Refusal(this.reason);

  /// Why the run was refused.
  final LoadRefusal reason;
}

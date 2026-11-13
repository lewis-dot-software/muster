import '../model/codebase_name.dart';
import '../model/fetch_outcome.dart';
import 'scratch.dart';

/// What a scratch's make gave: the scratch, or why it could not be made.
sealed class Scratching {
  const Scratching();
}

/// A scratch made, at its codebase's pin.
final class Scratched extends Scratching {
  /// The make that gave [scratch].
  const Scratched(this.scratch);

  /// The scratch, the consumer's own to move until it is disposed of.
  final Scratch scratch;
}

/// A name no codebase of the load's manifests bears, so no scratch of it can
/// be made.
final class NotNamed extends Scratching {
  /// The make refused for [name].
  const NotNamed(this.name);

  /// The name asked for.
  final CodebaseName name;
}

/// A codebase the load's manifests name with no clone to make a scratch of:
/// a hosted one.
final class NoClone extends Scratching {
  /// The make refused for [name].
  const NoClone(this.name);

  /// The name asked for.
  final CodebaseName name;
}

/// A make that failed, leaving no scratch.
final class ScratchFailed extends Scratching {
  /// The make that failed for [failure].
  const ScratchFailed(this.failure);

  /// Why the scratch could not be made.
  final ActFailure failure;
}

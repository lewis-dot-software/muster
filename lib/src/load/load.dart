import '../model/codebase_name.dart';
import '../model/fetch_outcome.dart';
import '../model/load_refusal.dart';

/// What a load gave: every codebase its manifests name, each with its
/// outcome, or why it refused before any fetch.
sealed class Load {
  const Load();
}

/// A load whose manifests were read, every codebase they name given its
/// outcome.
final class Loaded extends Load {
  /// The load that gave [outcomes].
  const Loaded(this.outcomes);

  /// Each codebase's outcome, keyed by its name, in the manifests' order,
  /// each manifest's codebases in its own.
  final Map<CodebaseName, FetchOutcome> outcomes;
}

/// A load refused before any fetch.
final class Refused extends Load {
  /// The load refused for [reason].
  const Refused(this.reason);

  /// Why the load refused.
  final LoadRefusal reason;
}

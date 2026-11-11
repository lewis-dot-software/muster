import 'git_codebase.dart';

/// A manifest's codebases, in the order it names them.
extension type Manifest._(List<GitCodebase> codebases) {
  /// The manifest naming [codebases], in their order.
  Manifest(Iterable<GitCodebase> codebases)
    : codebases = .unmodifiable(codebases);
}

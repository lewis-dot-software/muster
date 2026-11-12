import 'package:muster/muster.dart';
import 'package:muster/src/cli/refusal_text.dart';
import 'package:test/test.dart';

import '../support/outcomes.dart';

/// What each refusal's line names, so a person can act on it.
List<String> _named(LoadRefusal refusal) => switch (refusal) {
  NoManifest() => ['muster.yaml', 'MUSTER_MANIFESTS'],
  NotManifestName(:final String path) => [path, '.yaml'],
  ManifestMissing(:final manifest) => [manifest.path],
  ManifestUnreadable(:final manifest, :final String reason) => [
    manifest.path,
    reason,
  ],
  ManifestInvalid(:final manifest, :final refusal) => [
    manifest.path,
    switch (refusal) {
      NotYaml(:final String reason) => reason,
      UnknownKey(:final path) || MissingKey(:final path) => path.dotted,
      BadValue(:final path, :final String written) =>
        '${path.dotted}: $written',
    },
  ],
  CodebaseNamedTwice(:final name, :final first, :final second) => [
    name.name,
    first.path,
    second.path,
  ],
  NoWorkingDirectory(:final String reason) => [reason],
  NoCache() => ['MUSTER_CACHE'],
};

void main() {
  for (final LoadRefusal refusal in everyRefusal) {
    test('a refusal of ${refusal.runtimeType} is one line naming what to '
        'act on', () {
      final String text = refusalText(refusal);
      expect(text, isNot(contains('\n')));
      for (final String named in _named(refusal)) {
        expect(text, contains(named));
      }
    });
  }
}

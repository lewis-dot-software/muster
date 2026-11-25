import 'package:grit/grit.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/parse_stamp.dart';
import 'package:muster/src/model/render_stamp.dart';
import 'package:muster/src/model/stamp.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';
import '../support/stamps.dart';

/// A git URL a manifest may write: any text but a line break or another
/// control character, a tab, quotes, a backslash, a space and letters past
/// ASCII among it.
final Gen<String> _anyUrl = .build(
  (Draw draw) =>
      '${draw(.element(['https://example.com/', '/srv/', 'git@example.com:', 'file:///']))}'
      '${draw(.string(alphabet: .of('aZ9\t"\'\\ é{}%#?&-.'), minLength: 1))}',
);

/// A root inside its repo whose parts hold a tab, quotes, a space and
/// letters past ASCII.
final Gen<String> _anyRoot = .list(
  .element(['app', 'b c', 'q"t', "it's", 'tab\there', 'é', '{x}']),
).map((List<String> parts) => parts.isEmpty ? '.' : parts.join('/'));

void main() {
  property('STO-18: A stamp written and then read gives back the values it '
      'was written from.', (Draw draw) {
    final Stamp drawn = draw(anyStamp, label: 'stamp');
    final Stamp stamp = switch (drawn.codebase) {
      Git() => (
        codebase: Git(
          draw(
            anyGitCodebase(urls: _anyUrl, roots: _anyRoot),
            label: 'git',
          ),
        ),
        packages: drawn.packages,
        unresolved: drawn.unresolved,
        sdk: drawn.sdk,
      ),
      Hosted() => drawn,
    };
    expect(parseStamp(renderStamp(stamp)), sameStamp(stamp));
  });
}

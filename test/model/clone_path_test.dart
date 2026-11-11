import 'package:glados/glados.dart';
import 'package:muster/src/model/cache_directory.dart';
import 'package:muster/src/model/clone_path.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:path/path.dart' as p;

import '../support/manifests.dart';

final CacheDirectory _cache = .of((
  variables: {'MUSTER_CACHE': '/cache'},
  os: .posix,
))!;

/// Two codebases, the second's URL the first's where [same] holds.
final Generator<(GitCodebase, GitCodebase)> _pair = any.combine3(
  any.gitCodebase(),
  any.gitCodebase(),
  any.bool,
  (GitCodebase a, GitCodebase b, bool same) => (
    a,
    same
        ? (
            name: b.name,
            url: a.url,
            commit: b.commit,
            root: b.root,
            toolchain: b.toolchain,
          )
        : b,
  ),
);

void main() {
  test('a clone stands in the cache, named by a SHA-256 in hexadecimal', () {
    final ClonePath clone = .of(_cache, .parse('https://example.com/a.git')!);
    expect(p.dirname(clone.path), '/cache');
    expect(p.basename(clone.path), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('a clone is joined in its cache\'s own path style', () {
    final ClonePath clone = .of(
      .of((variables: {'LOCALAPPDATA': r'C:\l'}, os: .windows))!,
      .parse('https://example.com/a.git')!,
    );
    expect(clone.path, matches(RegExp(r'^C:\\l\\muster\\[0-9a-f]{64}$')));
  });

  test('two spellings of one repo are two clones', () {
    expect(
      ClonePath.of(_cache, .parse('https://example.com/a.git')!),
      isNot(ClonePath.of(_cache, .parse('https://example.com/a.git/')!)),
    );
  });

  Glados(_pair).test(
    'Two codebases share a clone exactly when their URLs are the same string.',
    (input) {
      final (GitCodebase a, GitCodebase b) = input;
      expect(
        ClonePath.of(_cache, a.url) == .of(_cache, b.url),
        a.url.url == b.url.url,
      );
    },
  );
}

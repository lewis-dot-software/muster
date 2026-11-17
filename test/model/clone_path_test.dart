import 'package:grit/grit.dart';
import 'package:muster/src/model/cache_directory.dart';
import 'package:muster/src/model/clone_path.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/git_url.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/manifests.dart';

final CacheDirectory _cache = .of((
  variables: {'MUSTER_CACHE': '/cache'},
  os: .posix,
))!;

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

  test('a temporary clone\'s name opens with its clone\'s, then '
      '`.partial.`', () {
    final GitUrl url = .parse('https://example.com/a.git')!;
    expect(
      ClonePath.temporaryPrefix(url),
      '${p.basename(ClonePath.of(_cache, url).path)}.partial.',
    );
  });

  test('no name but a temporary clone\'s is read as one', () {
    final String hash = p.basename(
      ClonePath.of(_cache, .parse('https://example.com/a.git')!).path,
    );
    for (final String name in [
      hash,
      '$hash.claim',
      '$hash.partial.',
      '$hash.partialx',
      '$hash.left.partial',
      '${hash.toUpperCase()}.partial',
      '${hash.substring(1)}.partial',
      'a$hash.partial',
      '.clone-abc123',
      'notes.partial',
    ]) {
      expect(ClonePath.ofTemporary(_cache, name), isNull, reason: name);
    }
  });

  test('a temporary clone with no token, `<hash>.partial`, is read as its '
      'clone\'s', () {
    final ClonePath clone = .of(_cache, .parse('https://example.com/a.git')!);
    expect(
      ClonePath.ofTemporary(_cache, '${p.basename(clone.path)}.partial'),
      clone,
    );
  });

  test('a temporary clone is read in its cache\'s own path style', () {
    final CacheDirectory windows = .of((
      variables: {'LOCALAPPDATA': r'C:\l'},
      os: .windows,
    ))!;
    final GitUrl url = .parse('https://example.com/a.git')!;
    expect(
      ClonePath.ofTemporary(windows, '${ClonePath.temporaryPrefix(url)}a1'),
      ClonePath.of(windows, url),
    );
  });

  property(
    'A temporary clone\'s name is read back as the clone it is made for, '
    'whatever letters and digits its token holds.',
    (Draw draw) {
      final GitCodebase codebase = draw(anyGitCodebase(), label: 'codebase');
      final String token = draw(
        .string(alphabet: .lettersAndDigits, minLength: 1),
        label: 'token',
      );
      expect(
        ClonePath.ofTemporary(
          _cache,
          '${ClonePath.temporaryPrefix(codebase.url)}$token',
        ),
        ClonePath.of(_cache, codebase.url),
      );
    },
  );

  property(
    'Two codebases share a clone exactly when their URLs are the same string.',
    (Draw draw) {
      final GitCodebase a = draw(anyGitCodebase(), label: 'a');
      final GitCodebase other = draw(anyGitCodebase(), label: 'other');
      final bool same = draw(.boolean(), label: 'same');
      final GitCodebase b = same
          ? (
              name: other.name,
              url: a.url,
              commit: other.commit,
              root: other.root,
              toolchain: other.toolchain,
            )
          : other;
      expect(
        ClonePath.of(_cache, a.url) == .of(_cache, b.url),
        a.url.url == b.url.url,
      );
    },
  );
}

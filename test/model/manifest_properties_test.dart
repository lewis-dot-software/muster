import 'package:glados/glados.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/lock_key.dart';
import 'package:muster/src/model/manifest.dart';
import 'package:muster/src/model/manifest_merge.dart';
import 'package:muster/src/model/manifest_parse.dart';
import 'package:muster/src/model/merge_manifests.dart';
import 'package:muster/src/model/parse_manifest.dart';
import 'package:muster/src/model/repo_root.dart';
import 'package:muster/src/model/manifest_refusal.dart';
import 'package:muster/src/model/wanted.dart';

import '../support/manifests.dart';
import '../support/refusals.dart';

/// The keys muster knows at a manifest's top.
const Set<String> _topKeys = {'codebases'};

/// The keys muster knows in a git codebase.
const Set<String> _gitKeys = {'git', 'commit', 'root', 'toolchain'};

/// A key, a known one at either depth among them.
final Generator<String> _anyKey = any.either(
  any.choose([..._topKeys, ..._gitKeys]),
  any.nonEmptyLowercaseLetters,
);

/// [key], or a key it is not where it is one of [known].
String _unknownAmong(String key, Set<String> known) =>
    known.contains(key) ? '${key}x' : key;

/// A value its key cannot take: the key, and the text that refuses it.
enum _Bad { commit, toolchain, root, name }

/// How a full hash is made into a commit that is no full hash.
enum _CommitFault { cut, capital, stray, long }

/// How a root is made into one that leaves its repo.
enum _RootFault { climb, climbBack, absolute, drive, backslash }

/// How a pub package name is made into a name that is none.
enum _NameFault { lead, inner, empty }

/// A spelling of a root other than its normal one, or its normal one.
enum _Spelling { normal, dotSlash, doubleSlash, detour }

/// A key a codebase lacks, or the `hosted` key it holds.
enum _Gap { git, commit, toolchain, hosted }

/// A commit that is no full hash: a full one cut short, given a capital, given
/// a character no hash holds, or run one digit long.
final Generator<String> _badCommit = any.combine3(
  any.fullHash,
  any.choose(_CommitFault.values),
  any.intInRange(0, 1 << 16),
  (String hash, _CommitFault fault, int at) {
    final int i = at % hash.length;
    return switch (fault) {
      .cut => hash.substring(0, switch (at % (hash.length - 1) + 1) {
        40 => 41,
        final int cut => cut,
      }),
      .capital => hash.replaceRange(i, i + 1, 'ABCDEF'[at % 6]),
      .stray => hash.replaceRange(i, i + 1, 'gz- '[at % 4]),
      .long => '${hash}0',
    };
  },
);

/// A toolchain that is neither `dart` nor `flutter`.
final Generator<String> _badToolchain = any.either(
  any.choose(['Dart', 'FLUTTER', 'dart ', ' flutter', '']),
  any.nonEmptyLetters.map(
    (String word) => word == 'dart' || word == 'flutter' ? '${word}x' : word,
  ),
);

/// A root that leaves its repo: one that climbs above the top, an absolute
/// one, a drive's, or one in Windows' separators.
final Generator<String> _badRoot = any.combine3(
  any.normalRoot,
  any.choose(_RootFault.values),
  any.intInRange(0, 3),
  (String root, _RootFault fault, int more) => switch (fault) {
    .climb => '${'../' * (more + 1)}$root',
    .climbBack => '$root${'/..' * (root.split('/').length + 1 + more)}',
    .absolute => '/$root',
    .drive => 'C:/$root',
    .backslash => '..\\${root.replaceAll('/', '\\')}',
  },
);

/// A codebase name that is no pub package name.
final Generator<String> _badName = any.combine3(
  any.packageName,
  any.choose(_NameFault.values),
  any.choose(['-', '.', 'A', 'Z', ' ', 'é']),
  (String name, _NameFault fault, String char) => switch (fault) {
    .lead => '${'09_'[char.codeUnitAt(0) % 3]}$name',
    .inner => '${name[0]}$char${name.substring(1)}',
    .empty => '',
  },
);

final Generator<(_Bad, String)> _bad = any
    .choose(_Bad.values)
    .bind(
      (_Bad bad) => switch (bad) {
        .commit => _badCommit,
        .toolchain => _badToolchain,
        .root => _badRoot,
        .name => _badName,
      }.map((String text) => (bad, text)),
    );

/// [root] in [spelling], null where it is left out.
String? _respelt(RepoRoot root, _Spelling spelling) => switch (spelling) {
  .normal => root == .top ? null : root.path,
  .dotSlash => './${root.path}/',
  .doubleSlash => '${root.path}//',
  .detour => 'tool/../${root.path}',
};

/// The codebases [text] parses to, which must stand.
List<GitCodebase> _parsed(String text) => switch (parseManifest(text)) {
  ManifestParsed(:final Manifest manifest) => manifest.codebases,
  ManifestRefused(:final ManifestRefusal refusal) => throw TestFailure(
    'refused $refusal:\n$text',
  ),
};

void main() {
  Glados(
    any.combine4(
      any.gitCodebases(),
      any.intInRange(0, 1 << 16),
      any.intInRange(0, 1 << 16),
      _anyKey,
      (List<GitCodebase> codebases, int where, int at, String key) =>
          (codebases, where, at, key),
    ),
  ).test("A key muster does not know, at any depth, refuses the load, naming "
      "that key's path from the top.", (input) {
    final (List<GitCodebase> codebases, int where, int at, String drawn) =
        input;
    final List<Entry> entries = codebases.map(entryOf).toList();
    final int target = where % (entries.length + 1);
    if (target == entries.length) {
      final String key = _unknownAmong(drawn, _topKeys);
      expect(
        parseManifest(renderManifest(entries, top: [(key, 'x')])),
        unknownKey([key]),
      );
      return;
    }
    final String key = _unknownAmong(drawn, _gitKeys);
    final (String name, List<Field> fields) = entries[target];
    entries[target] = (
      name,
      [...fields]..insert(at % (fields.length + 1), (key, 'x')),
    );
    expect(
      parseManifest(renderManifest(entries)),
      unknownKey(['codebases', name, key]),
    );
  });

  Glados(
    any.combine3(
      any.someGitCodebases(),
      any.intInRange(0, 1 << 16),
      _bad,
      (List<GitCodebase> codebases, int where, (_Bad, String) bad) =>
          (codebases, where, bad),
    ),
  ).test("A value its key cannot take refuses the load, naming that key's "
      "path: a commit that is not a full hash, a toolchain that is not `dart` "
      "or `flutter`, a `root` that leaves its repo, or a codebase name that is "
      "not a pub package name, `[a-z][a-z0-9_]*`.", (input) {
    final (List<GitCodebase> codebases, int where, (_Bad bad, String text)) =
        input;
    final List<Entry> entries = codebases.map(entryOf).toList();
    final int target = where % entries.length;
    final (String name, List<Field> fields) = entries[target];
    final String key;
    final Wanted wanted;
    switch (bad) {
      case .name:
        entries[target] = (text, fields);
        expect(
          parseManifest(renderManifest(entries)),
          badValue(['codebases', text], .packageName),
        );
        return;
      case .commit:
        (key, wanted) = ('commit', .fullHash);
      case .toolchain:
        (key, wanted) = ('toolchain', .toolchain);
      case .root:
        (key, wanted) = ('root', .rootInsideRepo);
    }
    entries[target] = (
      name,
      [
        for (final Field field in fields)
          if (field.$1 != key) field,
        (key, text),
      ],
    );
    expect(
      parseManifest(renderManifest(entries)),
      badValue(['codebases', name, key], wanted),
    );
  });

  Glados(
    any.combine3(
      any.someGitCodebases(),
      any.intInRange(0, 1 << 16),
      any.choose(_Gap.values),
      (List<GitCodebase> codebases, int where, _Gap gap) =>
          (codebases, where, gap),
    ),
  ).test("A codebase missing `git`, `commit` or `toolchain` refuses the load, "
      "and so does a `hosted` key until `v0.2.0`.", (input) {
    final (List<GitCodebase> codebases, int where, _Gap gap) = input;
    final List<Entry> entries = codebases.map(entryOf).toList();
    final int target = where % entries.length;
    final (String name, List<Field> fields) = entries[target];
    final String key = gap.name;
    switch (gap) {
      case .hosted:
        entries[target] = (name, [...fields, (key, 'args')]);
        expect(
          parseManifest(renderManifest(entries)),
          unknownKey(['codebases', name, key]),
        );
      case .git || .commit || .toolchain:
        entries[target] = (
          name,
          [
            for (final Field field in fields)
              if (field.$1 != key) field,
          ],
        );
        expect(
          parseManifest(renderManifest(entries)),
          missingKey(['codebases', name, key]),
        );
    }
  });

  Glados(
    any.list(
      any.gitCodebases(names: any.choose(['a', 'b', 'c', 'd', 'e', 'f'])),
    ),
  ).test("A parse gives the codebases back in the manifests' order, each "
      "under its own name, and a name met twice across the manifests of one "
      "load refuses it.", (List<List<GitCodebase>> manifests) {
    final ManifestMerge merge = mergeManifests([
      for (final List<GitCodebase> codebases in manifests)
        .new(_parsed(renderManifest(codebases.map(entryOf).toList()))),
    ]);
    final Map<String, int> seen = {};
    for (final (int index, List<GitCodebase> codebases) in manifests.indexed) {
      for (final GitCodebase codebase in codebases) {
        if (seen[codebase.name.name] case final int first) {
          expect(
            merge,
            isA<NamedTwice>()
                .having((n) => n.name, 'name', codebase.name)
                .having((n) => n.first, 'first', first)
                .having((n) => n.second, 'second', index),
          );
          return;
        }
        seen[codebase.name.name] = index;
      }
    }
    expect(
      merge,
      isA<Merged>().having((m) => m.codebases, 'codebases', [
        for (final List<GitCodebase> codebases in manifests) ...codebases,
      ]),
    );
  });

  final Generator<GitCodebase> nearby = any.gitCodebase(
    urls: any.choose(['/srv/a.git', '/srv/b.git']),
    commits: any.choose(['ab' * 20, 'cd' * 20]),
    roots: any.choose(['.', 'pkgs']),
  );
  Glados(
    any.combine5(
      nearby,
      nearby,
      any.gitCodebases(),
      any.choose(_Spelling.values),
      any.bool,
      (
        GitCodebase a,
        GitCodebase b,
        List<GitCodebase> others,
        _Spelling spelling,
        bool reversed,
      ) => (a, b, others, spelling, reversed),
    ),
  ).test("Two codebases share a kept lock's key exactly when they agree on "
      "URL, commit, `root` and toolchain, and no other change to a manifest "
      "moves the key.", (input) {
    final (
      GitCodebase a,
      GitCodebase b,
      List<GitCodebase> others,
      _Spelling spelling,
      bool reversed,
    ) = input;
    expect(
      LockKey.of(a) == LockKey.of(b),
      a.url == b.url &&
          a.commit == b.commit &&
          a.root == b.root &&
          a.toolchain == b.toolchain,
    );

    const String renamed = 'renamed';
    final String? root = _respelt(a.root, spelling);
    final List<Field> fields = [
      ('git', a.url.url),
      ('commit', a.commit.hash),
      if (root != null) ('root', root),
      ('toolchain', a.toolchain.name),
    ];
    final List<GitCodebase> parsed = _parsed(
      renderManifest([
        for (final GitCodebase other in others)
          if (other.name.name != renamed) entryOf(other),
        (renamed, reversed ? fields.reversed.toList() : fields),
      ]),
    );
    expect(LockKey.of(parsed.last), LockKey.of(a));
  });
}

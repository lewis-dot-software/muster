import 'package:glados/glados.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/lock_key.dart';
import 'package:muster/src/model/manifest.dart';
import 'package:muster/src/model/manifest_merge.dart';
import 'package:muster/src/model/manifest_parse.dart';
import 'package:muster/src/model/merge_manifests.dart';
import 'package:muster/src/model/parse_manifest.dart';
import 'package:muster/src/model/repo_root.dart';
import 'package:muster/src/model/resolution.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:muster/src/model/manifest_refusal.dart';
import 'package:muster/src/model/wanted.dart';

import '../support/lines_printed.dart';
import '../support/manifests.dart';
import '../support/refusals.dart';

/// The keys muster knows at a manifest's top.
const Set<String> _topKeys = {'codebases'};

/// The keys muster knows in a git codebase alone.
const Set<String> _gitKeys = {'git', 'commit', 'root'};

/// The keys muster knows in a hosted codebase alone.
const Set<String> _hostedKeys = {'hosted', 'version', 'resolution'};

/// The keys muster knows in a codebase of either kind.
const Set<String> _codebaseKeys = {..._gitKeys, ..._hostedKeys, 'toolchain'};

/// A key, a known one at either depth among them.
final Generator<String> _anyKey = any.either(
  any.choose([..._topKeys, ..._codebaseKeys]),
  any.nonEmptyLowercaseLetters,
);

/// The keys of the kind [codebase] is not.
Set<String> _otherKeys(Codebase codebase) => switch (codebase) {
  Git() => _hostedKeys,
  Hosted() => _gitKeys,
};

/// [key], or a key it is not where it is one of [known].
String _unknownAmong(String key, Set<String> known) =>
    known.contains(key) ? '${key}x' : key;

/// A directive the YAML reader warns of: one of a name it does not know, with
/// or without a parameter, or a `%YAML` of 1.3 or later.
final Generator<String> _warnedDirective = any.either(
  any.combine2(
    any.nonEmptyLetters,
    any.lowercaseLetters,
    (String name, String parameter) => switch (name) {
      'YAML' || 'TAG' => '%${name}X $parameter',
      _ => '%$name $parameter',
    },
  ),
  any.intInRange(3, 100).map((int minor) => '%YAML 1.$minor'),
);

/// A value its key cannot take: the key, and the text that refuses it.
enum _Bad { commit, toolchain, root, name }

/// How a full hash is made into a commit that is no full hash.
enum _CommitFault { cut, capital, stray, long }

/// How a root is made into one that leaves its repo.
enum _RootFault { climb, climbBack, absolute, drive, backslash }

/// How a codebase name is made into a name that is none.
enum _NameFault { lead, inner, empty }

/// How a pub package's name is made into one pub refuses: a word pub
/// reserves, a digit before it, a character no name holds inside it, a `.`
/// before or after it, two `.` inside it, a digit opening a part after a
/// `.`, or the empty name.
enum _PackageFault {
  reserved,
  lead,
  inner,
  dotLead,
  dotTrail,
  dots,
  partLead,
  empty,
}

/// A spelling of a root other than its normal one, or its normal one.
enum _Spelling { normal, dotSlash, doubleSlash, detour }

/// A key a git codebase lacks, or a hosted one does.
enum _Gap { git, commit, gitToolchain, hosted, version, hostedToolchain }

/// A hosted codebase's value its key cannot take.
enum _HostedBad { package, version }

/// How a version is made into one pub cannot read.
enum _VersionFault {
  short,
  long,
  prefix,
  caret,
  atLeast,
  emptyPre,
  badPre,
  pad,
  huge,
  word,
}

/// How a codebase is made into one of both kinds or of neither.
enum _KindFault { both, neither }

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

/// A toolchain that names no [Toolchain]: one of each written in capitals,
/// capitalised or padded, the empty word, or any other word.
final Generator<String> _badToolchain = any.either(
  any.choose([
    for (final Toolchain(:String name) in Toolchain.values) ...[
      name.toUpperCase(),
      '${name[0].toUpperCase()}${name.substring(1)}',
      '$name ',
      ' $name',
    ],
    '',
  ]),
  any.nonEmptyLetters.map(
    (String word) =>
        Toolchain.values.asNameMap().containsKey(word) ? '${word}x' : word,
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

/// A codebase name that is none.
final Generator<String> _badName = any.combine3(
  any.codebaseName,
  any.choose(_NameFault.values),
  any.choose(['-', '.', 'A', 'Z', ' ', 'é']),
  (String name, _NameFault fault, String char) => switch (fault) {
    .lead => '${'09_'[char.codeUnitAt(0) % 3]}$name',
    .inner => '${name[0]}$char${name.substring(1)}',
    .empty => '',
  },
);

/// A pub package's name that pub refuses, each fault of [_PackageFault]'s,
/// a reserved word in its own case, in capitals or capitalised.
final Generator<String> _badPackage = any.combine4(
  any.packageName,
  any.choose(_PackageFault.values),
  any.choose(pubReserved.toList()),
  any.intInRange(0, 1 << 16),
  (String name, _PackageFault fault, String word, int at) => switch (fault) {
    .reserved => switch (at % 3) {
      0 => word,
      1 => word.toUpperCase(),
      _ => '${word[0].toUpperCase()}${word.substring(1)}',
    },
    .lead => '${at % 10}$name',
    .inner =>
      '${name[0]}${['-', ' ', 'é', '@', '/', '+'][at % 6]}${name.substring(1)}',
    .dotLead => '.$name',
    .dotTrail => '$name.',
    .dots => '$name..$name',
    .partLead => '$name.${at % 10}$name',
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

/// A version pub cannot read: a canonical one cut to two parts, run to four,
/// given a `v` or a constraint's operator before it, given an empty or a
/// broken pre-release, padded, given a part past any integer, or a word.
final Generator<String> _badVersion = any.combine3(
  any.canonicalVersion,
  any.choose(_VersionFault.values),
  any.intInRange(0, 1 << 16),
  (String version, _VersionFault fault, int at) {
    final String core = version.split(RegExp('[-+]')).first;
    return switch (fault) {
      .short => core.substring(0, core.lastIndexOf('.')),
      .long => '$core.${at % 10}',
      .prefix => 'v$version',
      .caret => '^$version',
      .atLeast => '>=$version',
      .emptyPre => '$core-',
      .badPre => '$core-${'_! '[at % 3]}a',
      .pad => at.isEven ? ' $version' : '$version ',
      .huge => '${'9' * 20}.${core.substring(core.indexOf('.') + 1)}',
      .word => ['any', '', 'latest', 'one.two.three'][at % 4],
    };
  },
);

/// A resolution that is neither `alone` nor `as-dependency`: one of each in
/// capitals, capitalised, padded or in another case's spelling, the empty
/// word, or any other word.
final Generator<String> _badResolution = any.either(
  any.choose(
    {
      for (final Resolution(:String word) in Resolution.values) ...[
        word.toUpperCase(),
        '${word[0].toUpperCase()}${word.substring(1)}',
        '$word ',
        ' $word',
        word.replaceAll('-', '_'),
        word.replaceAll('-', ''),
      ],
      'asDependency',
      'dependency',
      '',
    }.where((String word) => Resolution.parse(word) == null).toList(),
  ),
  any.nonEmptyLetters.map(
    (String word) => Resolution.parse(word) == null ? word : '${word}x',
  ),
);

/// [version] with [noughts] more leading noughts on each of its first three
/// parts, a spelling pub reads as the same version.
String _respeltVersion(String version, int noughts) =>
    version.replaceFirstMapped(
      RegExp(r'^(\d+)\.(\d+)\.(\d+)'),
      (Match m) => [
        for (final int i in [1, 2, 3]) '${'0' * noughts}${m[i]}',
      ].join('.'),
    );

/// [root] in [spelling], null where it is left out.
String? _respelt(RepoRoot root, _Spelling spelling) => switch (spelling) {
  .normal => root == .top ? null : root.path,
  .dotSlash => './${root.path}/',
  .doubleSlash => '${root.path}//',
  .detour => 'tool/../${root.path}',
};

/// The codebases [text] parses to, which must stand.
List<Codebase> _parsed(String text) => switch (parseManifest(text)) {
  ManifestParsed(:final Manifest manifest) => manifest.codebases,
  ManifestRefused(:final ManifestRefusal refusal) => throw TestFailure(
    'refused $refusal:\n$text',
  ),
};

/// [codebases] with [codebase] in at [where], in place of any other of its
/// name, and the index it stands at.
(List<Codebase>, int) _with(
  List<Codebase> codebases,
  Codebase codebase,
  int where,
) {
  final List<Codebase> others = [
    for (final Codebase other in codebases)
      if (other.name != codebase.name) other,
  ];
  final int at = where % (others.length + 1);
  return ([...others]..insert(at, codebase), at);
}

void main() {
  Glados(
    any.combine4(
      any.codebases(),
      any.intInRange(0, 1 << 16),
      any.intInRange(0, 1 << 16),
      _anyKey,
      (List<Codebase> codebases, int where, int at, String key) =>
          (codebases, where, at, key),
    ),
  ).test("A key muster does not know, at any depth, refuses the load, naming "
      "that key's path from the top.", (input) {
    final (List<Codebase> codebases, int where, int at, String drawn) = input;
    final List<Entry> entries = codebases.map(anyEntryOf).toList();
    final int target = where % (entries.length + 1);
    if (target == entries.length) {
      final String key = _unknownAmong(drawn, _topKeys);
      expect(
        parseManifest(renderManifest(entries, top: [(key, 'x')])),
        unknownKey([key]),
      );
      return;
    }
    final String key = _unknownAmong(drawn, _codebaseKeys);
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
      "not `[a-z][a-z0-9_]*`.", (input) {
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
          badValue(['codebases', text], .codebaseName),
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
    any.combine5(
      any.codebases(),
      any.hostedCodebase(),
      any.intInRange(0, 1 << 16),
      any.intInRange(0, 3),
      any.either(
        any
            .choose(_HostedBad.values)
            .bind(
              (_HostedBad bad) => switch (bad) {
                .package => _badPackage,
                .version => _badVersion,
              }.map((String text) => (bad, text)),
            ),
        any.always<(_HostedBad, String)?>(null),
      ),
      (
        List<Codebase> codebases,
        HostedCodebase codebase,
        int where,
        int noughts,
        (_HostedBad, String)? bad,
      ) => (codebases, codebase, where, noughts, bad),
    ),
  ).test("A hosted codebase's `hosted` is a pub package name and its "
      "`version` a version pub reads, and any other value refuses the load, "
      "naming its key's path.", (input) {
    final (
      List<Codebase> others,
      HostedCodebase codebase,
      int where,
      int noughts,
      (_HostedBad, String)? bad,
    ) = input;
    final (List<Codebase> codebases, int target) = _with(
      others,
      Hosted(codebase),
      where,
    );
    final List<Entry> entries = codebases.map(anyEntryOf).toList();
    final (String name, List<Field> fields) = entries[target];
    switch (bad) {
      case null:
        entries[target] = (
          name,
          [
            for (final Field field in fields)
              field.$1 == 'version'
                  ? ('version', _respeltVersion(field.$2, noughts))
                  : field,
          ],
        );
        expect(_parsed(renderManifest(entries)), codebases);
      case (final _HostedBad which, final String text):
        final (String key, Wanted wanted) = switch (which) {
          .package => ('hosted', .packageName),
          .version => ('version', .version),
        };
        entries[target] = (
          name,
          [
            for (final Field field in fields)
              field.$1 == key ? (key, text) : field,
          ],
        );
        expect(
          parseManifest(renderManifest(entries)),
          badValue(['codebases', name, key], wanted),
        );
    }
  });

  Glados(
    any.combine4(
      any.codebases(),
      any.hostedCodebase(),
      any.intInRange(0, 1 << 16),
      any.either(_badResolution, any.always<String?>(null)),
      (
        List<Codebase> codebases,
        HostedCodebase codebase,
        int where,
        String? bad,
      ) => (codebases, codebase, where, bad),
    ),
  ).test("A `resolution` left out reads as `alone`, and any value but "
      "`alone` or `as-dependency` refuses.", (input) {
    final (
      List<Codebase> others,
      HostedCodebase codebase,
      int where,
      String? bad,
    ) = input;
    final (List<Codebase> codebases, int target) = _with(
      others,
      Hosted(codebase),
      where,
    );
    final List<Entry> entries = codebases.map(anyEntryOf).toList();
    final (String name, List<Field> fields) = entries[target];
    final List<Field> rest = [
      for (final Field field in fields)
        if (field.$1 != 'resolution') field,
    ];
    switch (bad) {
      case null:
        entries[target] = (name, rest);
        expect(
          _parsed(renderManifest(entries))[target],
          Hosted((
            name: codebase.name,
            package: codebase.package,
            version: codebase.version,
            resolution: .alone,
            toolchain: codebase.toolchain,
          )),
        );
      case final String text:
        entries[target] = (name, [...rest, ('resolution', text)]);
        expect(
          parseManifest(renderManifest(entries)),
          badValue(['codebases', name, 'resolution'], .resolution),
        );
    }
  });

  Glados(
    any.combine5(
      any.someCodebases(),
      any.intInRange(0, 1 << 16),
      any.choose(_KindFault.values),
      any.nonEmptyList(any.intInRange(0, 1 << 16)),
      any.bool,
      (
        List<Codebase> codebases,
        int where,
        _KindFault fault,
        List<int> others,
        bool toolchain,
      ) => (codebases, where, fault, others, toolchain),
    ),
  ).test("A codebase holding a key of both kinds, or of neither, refuses the "
      "load.", (input) {
    final (
      List<Codebase> codebases,
      int where,
      _KindFault fault,
      List<int> draws,
      bool toolchain,
    ) = input;
    final List<Entry> entries = codebases.map(anyEntryOf).toList();
    final int target = where % entries.length;
    final Codebase codebase = codebases[target];
    final (String name, List<Field> fields) = entries[target];
    switch (fault) {
      case .neither:
        entries[target] = (
          name,
          [
            for (final Field field in fields)
              if (toolchain && field.$1 == 'toolchain') field,
          ],
        );
        expect(
          parseManifest(renderManifest(entries)),
          refused(
            isA<MissingKind>().having(
              (MissingKind r) => r.path,
              'path',
              pathOf(['codebases', name]),
            ),
          ),
        );
      case .both:
        final List<String> other = _otherKeys(codebase).toList();
        final List<Field> mixed = [...fields];
        final Set<String> inserted = {};
        for (final int draw in draws) {
          if (inserted.add(other[draw % other.length])) {
            mixed.insert(draw % (mixed.length + 1), (
              other[draw % other.length],
              'x',
            ));
          }
        }
        // The first key of a kind's own sets the codebase's kind, and the
        // first of the other kind's is the one refused.
        final String first = mixed
            .firstWhere((Field field) => field.$1 != 'toolchain')
            .$1;
        final Set<String> own = _gitKeys.contains(first)
            ? _gitKeys
            : _hostedKeys;
        final String refusedKey = mixed
            .firstWhere(
              (Field field) =>
                  field.$1 != 'toolchain' && !own.contains(field.$1),
            )
            .$1;
        entries[target] = (name, mixed);
        expect(
          parseManifest(renderManifest(entries)),
          unknownKey(['codebases', name, refusedKey]),
        );
    }
  });

  Glados(
    any.combine3(
      any.someCodebases(),
      any.intInRange(0, 1 << 16),
      any.choose(_Gap.values),
      (List<Codebase> codebases, int where, _Gap gap) =>
          (codebases, where, gap),
    ),
  ).test("A git codebase missing `git`, `commit` or `toolchain`, or a hosted "
      "one missing `hosted`, `version` or `toolchain`, refuses the load, "
      "naming that key's path.", (input) {
    final (List<Codebase> drawn, int where, _Gap gap) = input;
    final int at = where % drawn.length;
    final Codebase target = switch ((gap, drawn[at])) {
      (.git || .commit || .gitToolchain, Git() && final Codebase git) => git,
      (
        .hosted || .version || .hostedToolchain,
        Hosted() && final Codebase hosted,
      ) =>
        hosted,
      (.git || .commit || .gitToolchain, final Codebase other) => Git(
        codebase(other.name.name, '/srv/a.git', 'ab' * 20, '.', .dart),
      ),
      (.hosted || .version || .hostedToolchain, final Codebase other) => Hosted(
        hosted(other.name.name, 'args', '2.7.0', .alone, .dart),
      ),
    };
    final List<Codebase> codebases = [...drawn]..[at] = target;
    final List<Entry> entries = codebases.map(anyEntryOf).toList();
    final (String name, List<Field> fields) = entries[at];
    final String key = switch (gap) {
      .git => 'git',
      .commit => 'commit',
      .hosted => 'hosted',
      .version => 'version',
      .gitToolchain || .hostedToolchain => 'toolchain',
    };
    entries[at] = (
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
  });

  Glados(
    any.list(any.codebases(names: any.choose(['a', 'b', 'c', 'd', 'e', 'f']))),
  ).test("A parse gives the codebases back in the manifests' order, each "
      "under its own name, and a name met twice across the manifests of one "
      "load refuses it.", (List<List<Codebase>> manifests) {
    final ManifestMerge merge = mergeManifests([
      for (final List<Codebase> codebases in manifests)
        .new(_parsed(renderManifest(codebases.map(anyEntryOf).toList()))),
    ]);
    final Map<String, int> seen = {};
    for (final (int index, List<Codebase> codebases) in manifests.indexed) {
      for (final Codebase codebase in codebases) {
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
        for (final (int index, List<Codebase> codebases) in manifests.indexed)
          for (final Codebase codebase in codebases)
            (codebase: codebase, manifest: index),
      ]),
    );
  });

  Glados2(any.codebases(), _warnedDirective).test(
    'A directive the YAML reader warns of, opening a manifest, leaves its '
    'parse as it stands without one, and prints nothing.',
    (List<Codebase> codebases, String directive) {
      final String text = renderManifest(codebases.map(anyEntryOf).toList());
      late final List<Codebase> parsed;
      expect(
        linesPrinted(() => parsed = _parsed('$directive\n---\n$text')),
        isEmpty,
      );
      expect(parsed, codebases);
    },
  );

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
      LockKey.of(Git(a)) == LockKey.of(Git(b)),
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
    final List<Codebase> parsed = _parsed(
      renderManifest([
        for (final GitCodebase other in others)
          if (other.name.name != renamed) entryOf(other),
        (renamed, reversed ? fields.reversed.toList() : fields),
      ]),
    );
    expect(LockKey.of(parsed.last), LockKey.of(Git(a)));
  });

  final Generator<HostedCodebase> nearbyHosted = any.hostedCodebase(
    packages: any.choose(['args', 'path']),
    versions: any.choose(['1.0.0', '1.0.1', '1.0.0-dev.1']),
  );
  Glados(
    any.combine5(
      nearbyHosted,
      nearbyHosted,
      any.gitCodebase(),
      any.intInRange(0, 3),
      any.bool,
      (
        HostedCodebase a,
        HostedCodebase b,
        GitCodebase git,
        int noughts,
        bool reversed,
      ) => (a, b, git, noughts, reversed),
    ),
  ).test("Two hosted codebases' kept locks share a key exactly when their "
      "package, version, resolution and toolchain are the same, and never "
      "share one with a git codebase.", (input) {
    final (
      HostedCodebase a,
      HostedCodebase b,
      GitCodebase git,
      int noughts,
      bool reversed,
    ) = input;
    expect(
      LockKey.of(Hosted(a)) == LockKey.of(Hosted(b)),
      a.package == b.package &&
          a.version == b.version &&
          a.resolution == b.resolution &&
          a.toolchain == b.toolchain,
    );
    expect(LockKey.of(Hosted(a)), isNot(LockKey.of(Git(git))));

    final (String _, List<Field> fields) = hostedEntryOf(
      a,
      resolutionOut: true,
    );
    final List<Field> respelt = [
      for (final Field field in fields)
        field.$1 == 'version'
            ? ('version', _respeltVersion(field.$2, noughts))
            : field,
    ];
    final List<Codebase> parsed = _parsed(
      renderManifest([
        ('renamed', reversed ? respelt.reversed.toList() : respelt),
      ]),
    );
    expect(LockKey.of(parsed.single), LockKey.of(Hosted(a)));
  });
}

import 'package:grit/grit.dart';
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
import 'package:test/test.dart';

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

/// A key, a known one at either depth among them, and one its path quotes:
/// an empty one, one holding a `.` or a line break, and one opening on `"`.
final Gen<String> _anyKey = .oneOf([
  .element([..._topKeys, ..._codebaseKeys]),
  .string(alphabet: .lowerCase, minLength: 1),
  .element(['', 'a.b', '"a', 'a\nb', 'a\u2028b']),
]);

/// A character that breaks a line: a control character but a tab, or a line
/// break Unicode names.
final Gen<String> _breaking = .element([
  for (int code = 0; code < 0x20; code++)
    if (code != 0x09) .fromCharCode(code),
  for (int code = 0x7f; code < 0xa0; code++) .fromCharCode(code),
  '\u2028',
  '\u2029',
]);

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
final Gen<String> _warnedDirective = .oneOf([
  .build((Draw draw) {
    final String name = draw(.string(alphabet: .letters, minLength: 1));
    final String parameter = draw(.string(alphabet: .lowerCase));
    return switch (name) {
      'YAML' || 'TAG' => '%${name}X $parameter',
      _ => '%$name $parameter',
    };
  }),
  .integer(min: 3, max: 99).map((int minor) => '%YAML 1.$minor'),
]);

/// A key of a git codebase's whose value the manifest can refuse, the
/// codebase's name among them.
enum _Bad { git, commit, toolchain, root, name }

/// A git codebase's key whose value no character that breaks a line stands
/// in, with what its key wants.
enum _Unbroken {
  git(.gitUrl),
  root(.rootInsideRepo);

  const _Unbroken(this.wanted);

  /// What the key wants of its value.
  final Wanted wanted;
}

/// How a full hash is made into a commit that is no full hash.
enum _CommitFault { cut, capital, stray, long }

/// How a root is made into one that leaves its repo, or holds a `\`.
enum _RootFault { climb, climbBack, absolute, drive, backslash, separator }

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

/// A git URL git would not take as one: the empty one, or one opening on `-`,
/// which git would read as an option.
final Gen<String> _badUrl = .oneOf([
  .element(['']),
  .build((Draw draw) => '-${draw(.element(['', '-']))}${draw(anyGitUrl)}'),
]);

/// A commit that is no full hash: a full one cut short, given a capital, given
/// a character no hash holds, or run one digit long.
final Gen<String> _badCommit = .build((Draw draw) {
  final String hash = draw(anyFullHash);
  switch (draw(.element(_CommitFault.values))) {
    case .cut:
      return hash.substring(0, switch (draw(
        .integer(min: 1, max: hash.length - 1),
      )) {
        40 => 41,
        final int cut => cut,
      });
    case .capital:
      final int i = draw(.integer(min: 0, max: hash.length - 1));
      return hash.replaceRange(i, i + 1, draw(.element('ABCDEF'.split(''))));
    case .stray:
      final int i = draw(.integer(min: 0, max: hash.length - 1));
      return hash.replaceRange(i, i + 1, draw(.element('gz- '.split(''))));
    case .long:
      return '${hash}0';
  }
});

/// A toolchain that names no [Toolchain]: one of each written in capitals,
/// capitalised or padded, the empty word, or any other word.
final Gen<String> _badToolchain = .oneOf([
  .element([
    for (final Toolchain(:String name) in Toolchain.values) ...[
      name.toUpperCase(),
      '${name[0].toUpperCase()}${name.substring(1)}',
      '$name ',
      ' $name',
    ],
    '',
  ]),
  .string(alphabet: .letters, minLength: 1).map(
    (String word) =>
        Toolchain.values.asNameMap().containsKey(word) ? '${word}x' : word,
  ),
]);

/// A root that leaves its repo: one that climbs above the top, an absolute
/// one, a drive's, or one in Windows' separators, climbing or not.
final Gen<String> _badRoot = .build((Draw draw) {
  final String root = draw(anyNormalRoot);
  final _RootFault fault = draw(.element(_RootFault.values));
  final int more = draw(.integer(min: 0, max: 2));
  return switch (fault) {
    .climb => '${'../' * (more + 1)}$root',
    .climbBack => '$root${'/..' * (root.split('/').length + 1 + more)}',
    .absolute => '/$root',
    .drive => 'C:/$root',
    .backslash => '..\\${root.replaceAll('/', '\\')}',
    .separator => '$root\\a',
  };
});

/// A codebase name that is none.
final Gen<String> _badName = .build((Draw draw) {
  final String name = draw(anyCodebaseName);
  return switch (draw(.element(_NameFault.values))) {
    .lead => '${draw(.element(['0', '9', '_']))}$name',
    .inner =>
      '${name[0]}${draw(.element(['-', '.', 'A', 'Z', ' ', 'é']))}'
          '${name.substring(1)}',
    .empty => '',
  };
});

/// A pub package's name that pub refuses, each fault of [_PackageFault]'s,
/// a reserved word in its own case, in capitals or capitalised.
final Gen<String> _badPackage = .build((Draw draw) {
  final String name = draw(anyPackageName);
  switch (draw(.element(_PackageFault.values))) {
    case .reserved:
      final String word = draw(.element(pubReserved.toList()));
      return draw(
        .element([
          word,
          word.toUpperCase(),
          '${word[0].toUpperCase()}${word.substring(1)}',
        ]),
      );
    case .lead:
      return '${draw(.integer(min: 0, max: 9))}$name';
    case .inner:
      final String char = draw(.element(['-', ' ', 'é', '@', '/', '+']));
      return '${name[0]}$char${name.substring(1)}';
    case .dotLead:
      return '.$name';
    case .dotTrail:
      return '$name.';
    case .dots:
      return '$name..$name';
    case .partLead:
      return '$name.${draw(.integer(min: 0, max: 9))}$name';
    case .empty:
      return '';
  }
});

/// A version pub cannot read: a canonical one cut to two parts, run to four,
/// given a `v` or a constraint's operator before it, given an empty or a
/// broken pre-release, padded, given a part past any integer, or a word.
final Gen<String> _badVersion = .build((Draw draw) {
  final String version = draw(anyCanonicalVersion);
  final String core = version.split(RegExp('[-+]')).first;
  return switch (draw(.element(_VersionFault.values))) {
    .short => core.substring(0, core.lastIndexOf('.')),
    .long => '$core.${draw(.integer(min: 0, max: 9))}',
    .prefix => 'v$version',
    .caret => '^$version',
    .atLeast => '>=$version',
    .emptyPre => '$core-',
    .badPre => '$core-${draw(.element(['_', '!', ' ']))}a',
    .pad => draw(.element([' $version', '$version '])),
    .huge => '${'9' * 20}.${core.substring(core.indexOf('.') + 1)}',
    .word => draw(.element(['any', '', 'latest', 'one.two.three'])),
  };
});

/// A resolution that is neither `alone` nor `as-dependency`: one of each in
/// capitals, capitalised, padded or in another case's spelling, the empty
/// word, or any other word.
final Gen<String> _badResolution = .oneOf([
  .element(
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
  .string(
    alphabet: .letters,
    minLength: 1,
  ).map((String word) => Resolution.parse(word) == null ? word : '${word}x'),
]);

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

/// A codebase placed among others: the `codebases` it stands in, and the
/// index `at` it stands at.
typedef _Placed = (List<Codebase> codebases, int at);

/// [codebases] with [codebase] in at a place [draw] draws, in place of any
/// other of its name, and the index it stands at.
_Placed _with(Draw draw, List<Codebase> codebases, Codebase codebase) {
  final List<Codebase> others = [
    for (final Codebase other in codebases)
      if (other.name != codebase.name) other,
  ];
  final int at = draw(.integer(min: 0, max: others.length), label: 'target');
  return ([...others]..insert(at, codebase), at);
}

void main() {
  property("MAN-12: A key muster does not know, at the top or in a codebase, "
      "refuses the load, naming that key's path from the top.", (Draw draw) {
    final List<Codebase> codebases = draw(anyCodebases(), label: 'codebases');
    final List<Entry> entries = codebases.map(anyEntryOf).toList();
    final int target = draw(
      .integer(min: 0, max: entries.length),
      label: 'target',
    );
    if (target == entries.length) {
      final String key = _unknownAmong(draw(_anyKey, label: 'drawn'), _topKeys);
      expect(
        parseManifest(renderManifest(entries, top: [(key, 'x')])),
        unknownKey([key]),
      );
      return;
    }
    final (String name, List<Field> fields) = entries[target];
    final int at = draw(.integer(min: 0, max: fields.length), label: 'at');
    final String key = _unknownAmong(
      draw(_anyKey, label: 'drawn'),
      _codebaseKeys,
    );
    entries[target] = (name, [...fields]..insert(at, (key, 'x')));
    expect(
      parseManifest(renderManifest(entries)),
      unknownKey(['codebases', name, key]),
    );
  });

  property("MAN-17: A git URL or a `root` holding a character that breaks a "
      "line refuses the load, naming its key's path.", (Draw draw) {
    final List<GitCodebase> codebases = draw(
      someGitCodebases,
      label: 'codebases',
    );
    final List<Entry> entries = codebases.map(entryOf).toList();
    final int target = draw(
      .integer(min: 0, max: entries.length - 1),
      label: 'target',
    );
    final _Unbroken key = draw(.element(_Unbroken.values), label: 'key');
    final GitCodebase codebase = codebases[target];
    final String value = switch (key) {
      .git => codebase.url.url,
      .root => codebase.root.path,
    };
    final int at = draw(.integer(min: 0, max: value.length), label: 'at');
    final String breaking = draw(_breaking, label: 'breaking');
    entries[target] = (
      codebase.name.name,
      [
        for (final Field field in entries[target].$2)
          if (field.$1 != key.name) field,
        (key.name, value.replaceRange(at, at, breaking)),
      ],
    );
    expect(
      parseManifest(renderManifest(entries)),
      badValue(['codebases', codebase.name.name, key.name], key.wanted),
    );
  });

  property("MAN-8: A value its key cannot take refuses the load, naming that "
      "key's path: a git URL that is empty or opens on `-`, a commit that is "
      "not a full hash, a toolchain that is not `dart` or `flutter`, a `root` "
      r"that leaves its repo or holds a `\`, or a codebase name that is not "
      "`[a-z][a-z0-9_]*`.", (Draw draw) {
    final List<GitCodebase> codebases = draw(
      someGitCodebases,
      label: 'codebases',
    );
    final List<Entry> entries = codebases.map(entryOf).toList();
    final int target = draw(
      .integer(min: 0, max: entries.length - 1),
      label: 'target',
    );
    final _Bad bad = draw(.element(_Bad.values), label: 'bad');
    final String text = draw(switch (bad) {
      .git => _badUrl,
      .commit => _badCommit,
      .toolchain => _badToolchain,
      .root => _badRoot,
      .name => _badName,
    }, label: 'text');
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
      case .git:
        (key, wanted) = ('git', .gitUrl);
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

  property("MAN-9: A hosted codebase's `hosted` is a pub package name and its "
      "`version` a version pub reads, and any other text refuses the load, "
      "naming its key's path.", (Draw draw) {
    final List<Codebase> others = draw(anyCodebases(), label: 'others');
    final HostedCodebase codebase = draw(
      anyHostedCodebase(),
      label: 'codebase',
    );
    final (List<Codebase> codebases, int target) = _with(
      draw,
      others,
      Hosted(codebase),
    );
    final int noughts = draw(.integer(min: 0, max: 2), label: 'noughts');
    final _HostedBad? bad = draw(
      .oneOf([
        .element(_HostedBad.values),
        .element([null]),
      ]),
      label: 'bad',
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
      case final _HostedBad which:
        final String text = draw(switch (which) {
          .package => _badPackage,
          .version => _badVersion,
        }, label: 'text');
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

  property("MAN-13: A `resolution` left out reads as `alone`, and any value "
      "but `alone` or `as-dependency` refuses, naming its key's path.", (
    Draw draw,
  ) {
    final List<Codebase> others = draw(anyCodebases(), label: 'others');
    final HostedCodebase codebase = draw(
      anyHostedCodebase(),
      label: 'codebase',
    );
    final (List<Codebase> codebases, int target) = _with(
      draw,
      others,
      Hosted(codebase),
    );
    final String? bad = draw(
      .oneOf([
        _badResolution,
        .element([null]),
      ]),
      label: 'bad',
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

  property("MAN-11: A codebase holding no key of either kind refuses the load, "
      "naming the codebase's path, and one holding keys of both refuses at "
      "the first key of the kind its first kind's key does not name.", (
    Draw draw,
  ) {
    final List<Codebase> codebases = draw(someCodebases, label: 'codebases');
    final List<Entry> entries = codebases.map(anyEntryOf).toList();
    final int target = draw(
      .integer(min: 0, max: entries.length - 1),
      label: 'target',
    );
    final _KindFault fault = draw(.element(_KindFault.values), label: 'fault');
    final Codebase codebase = codebases[target];
    final (String name, List<Field> fields) = entries[target];
    switch (fault) {
      case .neither:
        final bool toolchain = draw(.boolean(), label: 'toolchain');
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
        final List<String> picks = draw(
          .list(.element(_otherKeys(codebase).toList()), minLength: 1),
          label: 'picks',
        );
        final List<Field> mixed = [...fields];
        final Set<String> inserted = {};
        for (final String pick in picks) {
          if (inserted.add(pick)) {
            final int at = draw(
              .integer(min: 0, max: mixed.length),
              label: 'at',
            );
            mixed.insert(at, (pick, 'x'));
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

  property("MAN-10: A git codebase missing `git`, `commit` or `toolchain`, or "
      "a hosted one missing `hosted`, `version` or `toolchain`, refuses the "
      "load, naming that key's path.", (Draw draw) {
    final List<Codebase> drawn = draw(someCodebases, label: 'drawn');
    final int at = draw(.integer(min: 0, max: drawn.length - 1), label: 'at');
    final _Gap gap = draw(.element(_Gap.values), label: 'gap');
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

  property("MAN-7: A parse gives the codebases back in the manifests' order, "
      "each under its own name, and the first name met twice across them "
      "refuses, naming it and the manifests it is met in.", (Draw draw) {
    final List<List<Codebase>> manifests = draw(
      .list(anyCodebases(names: .element(['a', 'b', 'c', 'd', 'e', 'f']))),
      label: 'manifests',
    );
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

  property(
    'MAN-20: A directive the YAML reader warns of, opening a manifest, leaves '
    'its parse as it stands without one, and prints nothing.',
    (Draw draw) {
      final List<Codebase> codebases = draw(anyCodebases(), label: 'codebases');
      final String directive = draw(_warnedDirective, label: 'directive');
      final String text = renderManifest(codebases.map(anyEntryOf).toList());
      late final List<Codebase> parsed;
      expect(
        linesPrinted(() => parsed = _parsed('$directive\n---\n$text')),
        isEmpty,
      );
      expect(parsed, codebases);
    },
  );

  final Gen<GitCodebase> nearby = anyGitCodebase(
    urls: .element(['/srv/a.git', '/srv/a.git/', '/srv/b.git']),
    commits: .element(['ab' * 20, 'cd' * 20]),
    roots: .element(['.', 'pkgs']),
  );
  property("MAN-4: Two git codebases share a kept lock's key exactly when they "
      "agree on URL as written, commit, `root` and toolchain, and neither a "
      "rename, a `root` spelt another way, the keys' order nor the codebases "
      "beside it moves the key.", (Draw draw) {
    final GitCodebase a = draw(nearby, label: 'a');
    final GitCodebase b = draw(nearby, label: 'b');
    final List<GitCodebase> others = draw(anyGitCodebases(), label: 'others');
    final _Spelling spelling = draw(
      .element(_Spelling.values),
      label: 'spelling',
    );
    final bool reversed = draw(.boolean(), label: 'reversed');
    expect(
      LockKey.of(Git(a)) == .of(Git(b)),
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

  final Gen<HostedCodebase> nearbyHosted = anyHostedCodebase(
    packages: .element(['args', 'path']),
    versions: .element(['1.0.0', '1.0.1', '1.0.0-dev.1']),
  );
  property("MAN-5: Two hosted codebases' kept locks share a key exactly when "
      "their package, version, resolution and toolchain are the same, and "
      "never share one with a git codebase.", (Draw draw) {
    final HostedCodebase a = draw(nearbyHosted, label: 'a');
    final HostedCodebase b = draw(nearbyHosted, label: 'b');
    final GitCodebase git = draw(anyGitCodebase(), label: 'git');
    final int noughts = draw(.integer(min: 0, max: 2), label: 'noughts');
    final bool reversed = draw(.boolean(), label: 'reversed');
    expect(
      LockKey.of(Hosted(a)) == .of(Hosted(b)),
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

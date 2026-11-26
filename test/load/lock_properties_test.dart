import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/kept_lock_path.dart';
import 'package:muster/src/model/lock_outcome.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/resolution.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/files_under.dart';
import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/locks.dart';
import '../support/manifests.dart';
import '../support/origin.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
import '../support/spy_runner.dart';
import '../support/write_file.dart';

/// One codebase of a draw: whether its commit holds an example, whether it
/// holds its packages' locks, the packages whose kept lock stands before the
/// lock, whether its manifest is the one `MUSTER_MANIFESTS` lists in place of
/// the root's, and whether locks no manifest names stray beside it: one of
/// its name at a key its values do not give, that one's partial, and its
/// own beside the manifest that does not name it.
typedef _Codebase = ({
  bool example,
  bool committed,
  Set<Package> kept,
  bool listed,
  bool strayed,
});

/// A codebase of a draw, its flags drawn in turn.
final Gen<_Codebase> _codebase = .build(
  (Draw draw) => (
    example: draw(.boolean()),
    committed: draw(.boolean()),
    kept: draw(.set(.element(Package.values))),
    listed: draw(.boolean()),
    strayed: draw(.boolean()),
  ),
);

/// The text a kept lock standing before a lock holds, which no resolve
/// writes, so a lock that rewrote it would show.
const String _standing = '# kept before the lock\n$lockText';

/// One hosted codebase of the closed cases: how it resolves, whether its
/// package serves an example, and which of its packages' kept locks stand
/// before the lock.
typedef _Hosted = ({
  Resolution resolution,
  bool example,
  Set<Package> standing,
});

/// A hosted codebase of a draw: the index `i` that names it, and the case
/// it is `drawn` as.
typedef _HostedDrawn = (int i, _Hosted drawn);

/// Every closed case of a hosted codebase, each subset of its packages
/// standing among them.
final List<_Hosted> _hostedCases = [
  for (final Resolution resolution in Resolution.values)
    for (final bool example in [false, true])
      for (final Set<Package> standing in [
        <Package>{},
        {.root},
        if (example) ...[
          {.example},
          {.root, .example},
        ],
      ])
        (resolution: resolution, example: example, standing: standing),
];

/// An order of [length] items, each index below [length] once, drawn as a
/// shuffle that takes each next item from those left.
Gen<List<int>> _orderOf(int length) => .build((Draw draw) {
  final List<int> left = [for (int i = 0; i < length; i++) i];
  return [
    for (int n = length; n > 0; n--)
      left.removeAt(draw(.integer(min: 0, max: n - 1))),
  ];
});

void main() {
  property(
    'MAN-1: `muster lock`: writes a kept lock for each package that '
    'needs one and has none, leaves every existing lock untouched, '
    'removes every lock and partial its manifest no longer names, so a '
    'second run changes nothing.',
    (Draw draw) => inTemp((Directory temp) async {
      final List<_Codebase> draws = draw(
        .list(_codebase, minLength: 1),
        label: 'draws',
      );
      final List<String> strays = draw(.list(anyCodebaseName), label: 'strays');
      final SpyRunner runner = .new(hermetic(temp));
      final Origin origin = await .make(temp, runner);
      final String listed = p.join(temp.path, 'elsewhere', 'listed.yaml');
      final List<GitCodebase> atRootManifest = [];
      final List<GitCodebase> inListed = [];
      final Map<KeptLockPath, bool> needed = {};
      final Set<KeptLockPath> standing = {};
      final List<String> gone = [];
      for (final (int i, _Codebase drawn) in draws.take(3).indexed) {
        final Commit pin = await origin.commit(null, {
          ...packageFiles('c$i', locked: drawn.committed),
          if (drawn.example)
            ...packageFiles(
              'c${i}_example',
              at: 'example',
              locked: drawn.committed,
            ),
        });
        await origin.ref('refs/heads/c$i', pin);
        final GitCodebase codebase = codebaseOf(origin, pin, name: 'c$i');
        final String manifest = drawn.listed ? listed : atRoot(temp);
        (drawn.listed ? inListed : atRootManifest).add(codebase);
        for (final Package package in [.root, if (drawn.example) .example]) {
          final KeptLockPath kept = keptOf(manifest, codebase, package);
          needed[kept] = !drawn.committed;
          if (drawn.kept.contains(package)) {
            await writeFile(kept.path, _standing);
            standing.add(kept);
          }
        }
        if (drawn.strayed) {
          final String stale = p.join(
            locksBeside(manifest).path,
            'c$i-${'0' * 64}.lock',
          );
          gone.addAll([
            stale,
            '$stale.partial',
            keptOf(drawn.listed ? atRoot(temp) : listed, codebase).path,
          ]);
        }
      }
      await writeManifest(atRoot(temp), atRootManifest);
      await writeManifest(listed, inListed);
      for (final (int i, String stray) in strays.take(2).indexed) {
        gone.add(
          p.join(
            locksBeside(i.isEven ? atRoot(temp) : listed).path,
            '$stray-gone.lock',
          ),
        );
      }
      for (final String stray in gone) {
        await writeFile(stray, lockText);
      }
      Future<Locking> lock() => loaderIn(
        temp,
        runner,
        variables: {'MUSTER_MANIFESTS': listed},
      ).lock();
      final Locking first = await lock();
      expect(first, isA<Locked>());
      expect(
        (first as Locked).outcomes.values,
        everyElement(isA<LocksWritten>()),
      );
      for (final MapEntry<KeptLockPath, bool>(key: kept, value: need)
          in needed.entries) {
        final File file = .new(kept.path);
        if (standing.contains(kept)) {
          expect(await file.readAsString(), _standing);
        } else {
          expect(await file.exists(), need, reason: kept.path);
        }
      }
      for (final String stray in gone) {
        expect(await File(stray).exists(), isFalse, reason: stray);
      }
      Future<List<Map<String, String>>> locks() async => [
        for (final String manifest in [atRoot(temp), listed])
          if (await Directory(locksBeside(manifest).path).exists())
            await filesUnder(locksBeside(manifest).path),
      ];
      final List<Map<String, String>> written = await locks();
      expect(
        await lock(),
        lockedWith({
          for (final GitCodebase codebase in [...atRootManifest, ...inListed])
            codebase.name.name: wrote(const []),
        }),
      );
      expect(await locks(), written);
    }),
    settings: .new(runs: 10, shrinkSteps: gitShrinks),
  );

  property(
    'MAN-6: `muster lock` writes the kept locks a hosted package and its '
    'example lack, leaving those that stand, and a load after it gives '
    '`Fetched`.',
    (Draw draw) => inTemp((Directory temp) async {
      final List<int> order = draw(
        _orderOf(_hostedCases.length),
        label: 'order',
      );
      final PackageServer server = await .start();
      try {
        final SpyRunner runner = .new({
          ...hermetic(temp),
          ...pubVariables(temp, server),
        });
        // Every closed case at once, in an order of the draw's.
        final List<_HostedDrawn> cases = [
          for (final int i in order) (i, _hostedCases[i]),
        ];
        final List<HostedCodebase> codebases = [
          for (final (int i, _Hosted drawn) in cases)
            hostedOf('p$i', name: 'c$i', resolution: drawn.resolution),
        ];
        for (final (int i, _Hosted drawn) in cases) {
          serveLeaf(server, 'p$i', '1.0.0', example: drawn.example);
        }
        await writeFile(
          atRoot(temp),
          renderManifest(codebases.map(hostedEntryOf).toList()),
        );
        Set<Package> packagesOf(_Hosted drawn) => {
          .root,
          if (drawn.example) .example,
        };
        List<KeptLockPath> keptLocks(
          HostedCodebase codebase,
          Set<Package> of,
        ) => [
          for (final Package package in Package.values)
            if (of.contains(package))
              keptLockOf(locksBeside(atRoot(temp)), Hosted(codebase), package),
        ];
        // A lock with none standing writes every one.
        expect(
          await loaderIn(temp, runner).lock(),
          lockedWith({
            for (final (int at, (_, _Hosted drawn)) in cases.indexed)
              codebases[at].name.name: wrote(
                keptLocks(codebases[at], packagesOf(drawn)),
              ),
          }),
        );
        final Map<KeptLockPath, String> kept = {};
        for (final (int at, (_, _Hosted drawn)) in cases.indexed) {
          for (final KeptLockPath lock in keptLocks(
            codebases[at],
            packagesOf(drawn),
          )) {
            kept[lock] = await File(lock.path).readAsString();
          }
          for (final KeptLockPath lock in keptLocks(
            codebases[at],
            packagesOf(drawn).difference(drawn.standing),
          )) {
            await File(lock.path).delete();
          }
        }
        // A lock with some standing writes those lacking alone.
        expect(
          await loaderIn(temp, runner).lock(),
          lockedWith({
            for (final (int at, (_, _Hosted drawn)) in cases.indexed)
              codebases[at].name.name: wrote(
                keptLocks(
                  codebases[at],
                  packagesOf(drawn).difference(drawn.standing),
                ),
              ),
          }),
        );
        for (final MapEntry<KeptLockPath, String>(key: lock, value: text)
            in kept.entries) {
          expect(await File(lock.path).readAsString(), text, reason: lock.path);
        }
        expect(
          await loaderIn(temp, runner).load(),
          loadedWith({
            for (final HostedCodebase codebase in codebases)
              codebase.name.name: fetchedAt(
                '${checkoutAt(temp, codebase.name.name)}/'
                '${codebase.package.name}-1.0.0',
              ),
          }),
        );
      } finally {
        await server.close();
      }
    }),
    settings: .new(runs: 1, shrinkSteps: gitShrinks),
  );
}

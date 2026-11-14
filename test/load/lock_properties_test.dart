import 'dart:io';

import 'package:glados/glados.dart';
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

import '../support/files_under.dart';
import '../support/git.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/locks.dart';
import '../support/manifests.dart';
import '../support/origin.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
import '../support/shrinking_at_most.dart';
import '../support/spy_runner.dart';
import '../support/write_file.dart';

/// One codebase of a draw: whether its commit holds an example, whether it
/// holds its packages' locks, whether a kept lock stands for each package
/// before the lock, and whether its manifest is the one `MUSTER_MANIFESTS`
/// lists in place of the root's.
typedef _Codebase = ({bool example, bool committed, bool kept, bool listed});

final Generator<_Codebase> _codebase = any.combine4(
  any.bool,
  any.bool,
  any.bool,
  any.bool,
  (bool example, bool committed, bool kept, bool listed) =>
      (example: example, committed: committed, kept: kept, listed: listed),
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

void main() {
  Glados2(
    any.nonEmptyList(_codebase).shrinkingAtMost(gitTries),
    any.list(any.codebaseName).shrinkingAtMost(gitTries),
    .new(numRuns: 10),
  ).test(
    '`muster lock` writes a kept lock for each codebase that needs one and '
    'has none, leaves every existing lock untouched, and removes every lock '
    'its manifest no longer names, so a second run changes nothing.',
    (List<_Codebase> draws, List<String> strays) => inTemp((
      Directory temp,
    ) async {
      final SpyRunner runner = .new(hermetic(temp));
      final Origin origin = await .make(temp, runner);
      final String listed = p.join(temp.path, 'elsewhere', 'listed.yaml');
      final List<GitCodebase> atRootManifest = [];
      final List<GitCodebase> inListed = [];
      final Map<KeptLockPath, bool> needed = {};
      final Set<KeptLockPath> standing = {};
      for (final (int i, _Codebase draw) in draws.take(3).indexed) {
        final Commit pin = await origin.commit(null, {
          ...packageFiles('c$i', locked: draw.committed),
          if (draw.example)
            ...packageFiles(
              'c${i}_example',
              at: 'example',
              locked: draw.committed,
            ),
        });
        await origin.ref('refs/heads/c$i', pin);
        final GitCodebase codebase = codebaseOf(origin, pin, name: 'c$i');
        final String manifest = draw.listed ? listed : atRoot(temp);
        (draw.listed ? inListed : atRootManifest).add(codebase);
        for (final Package package in [.root, if (draw.example) .example]) {
          final KeptLockPath kept = keptOf(manifest, codebase, package);
          needed[kept] = !draw.committed;
          if (draw.kept) {
            await writeFile(kept.path, _standing);
            standing.add(kept);
          }
        }
      }
      await writeManifest(atRoot(temp), atRootManifest);
      await writeManifest(listed, inListed);
      final List<String> gone = [
        for (final (int i, String stray) in strays.take(2).indexed)
          p.join(
            locksBeside(i.isEven ? atRoot(temp) : listed).path,
            '$stray-gone.lock',
          ),
      ];
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
  );

  Glados(any.int.shrinkingAtMost(gitTries), .new(numRuns: 1)).test(
    '`muster lock` writes the kept locks a hosted package and its example '
    'lack, and a load after it gives `Fetched`.',
    (int seed) => inTemp((Directory temp) async {
      final PackageServer server = await .start();
      try {
        final SpyRunner runner = .new({
          ...hermetic(temp),
          ...pubVariables(temp, server),
        });
        // Every closed case at once, in an order of the draw's.
        final List<(int, _Hosted)> cases = [..._hostedCases.indexed]
          ..shuffle(.new(seed));
        final List<HostedCodebase> codebases = [
          for (final (int i, _Hosted draw) in cases)
            hostedOf('p$i', name: 'c$i', resolution: draw.resolution),
        ];
        for (final (int i, _Hosted draw) in cases) {
          serveLeaf(server, 'p$i', '1.0.0', example: draw.example);
        }
        await writeFile(
          atRoot(temp),
          renderManifest(codebases.map(hostedEntryOf).toList()),
        );
        Set<Package> packagesOf(_Hosted draw) => {
          .root,
          if (draw.example) .example,
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
            for (final (int at, (_, _Hosted draw)) in cases.indexed)
              codebases[at].name.name: wrote(
                keptLocks(codebases[at], packagesOf(draw)),
              ),
          }),
        );
        final Map<KeptLockPath, String> kept = {};
        for (final (int at, (_, _Hosted draw)) in cases.indexed) {
          for (final KeptLockPath lock in keptLocks(
            codebases[at],
            packagesOf(draw),
          )) {
            kept[lock] = await File(lock.path).readAsString();
          }
          for (final KeptLockPath lock in keptLocks(
            codebases[at],
            packagesOf(draw).difference(draw.standing),
          )) {
            await File(lock.path).delete();
          }
        }
        // A lock with some standing writes those lacking alone.
        expect(
          await loaderIn(temp, runner).lock(),
          lockedWith({
            for (final (int at, (_, _Hosted draw)) in cases.indexed)
              codebases[at].name.name: wrote(
                keptLocks(
                  codebases[at],
                  packagesOf(draw).difference(draw.standing),
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
  );
}

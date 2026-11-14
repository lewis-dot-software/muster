import 'dart:convert';
import 'dart:io';

import '../model/around_pubspec.dart';
import '../model/at_commit.dart';
import '../model/checkout.dart';
import '../model/checkout_found.dart';
import '../model/checkout_path.dart';
import '../model/choose_checkout_step.dart';
import '../model/choose_locks.dart';
import '../model/at_commit_files.dart';
import '../model/clone_path.dart';
import '../model/codebase.dart';
import '../model/consumer_root.dart';
import '../model/content_hash.dart';
import '../model/fetch_outcome.dart';
import '../model/git_codebase.dart';
import '../model/hosted_codebase.dart';
import '../model/kept_lock_path.dart';
import '../model/lock_choice.dart';
import '../model/lock_source.dart';
import '../model/locks_directory.dart';
import '../model/locks_lacking.dart';
import '../model/package.dart';
import '../model/package_path.dart';
import '../model/parse_stamp.dart';
import '../model/partial_lock_path.dart';
import '../model/hosted_resolves.dart';
import '../model/pubspec_overrides.dart';
import '../model/pubspec_overrides_path.dart';
import '../model/pubspec_path.dart';
import '../model/read_at_commit.dart';
import '../model/repo_path.dart';
import '../model/read_status.dart';
import '../model/render_stamp.dart';
import '../model/sdk_version.dart';
import '../model/stamp.dart';
import '../model/stamped_package.dart';
import '../model/stands.dart';
import '../model/survey.dart';
import '../model/surveyed_package.dart';
import '../model/unpack_command.dart';
import '../model/workspace_member.dart';
import '../model/worktree.dart';
import 'add_worktree.dart';
import 'cache.dart';
import 'claims.dart';
import 'file_act.dart';
import 'git_in.dart';
import 'git_on.dart';
import 'move_worktree.dart';
import 'bytes_if_there.dart';
import 'ran.dart';
import 'remove_directory.dart';
import 'remove_file.dart';
import 'runner.dart';
import 'sdk_versions.dart';
import 'store_fault.dart';

/// A consumer's checkouts, one per codebase under its root: a git codebase's
/// a worktree of its clone in a [Cache], and a hosted one's its package
/// unpacked, their processes run by a [Runner] and their acts held under
/// [Claims].
class Checkouts {
  /// The checkouts under [root], cloned into [_cache], their git and
  /// toolchains run by [_runner], each acted on under its claim in
  /// [_claims], and each toolchain's SDK version read from [_sdks].
  Checkouts(this.root, this._cache, this._runner, this._claims, this._sdks);

  /// The consumer's root, the checkouts under its `.dart_tool/muster/`.
  final ConsumerRoot root;

  final Cache _cache;

  final Runner _runner;

  final Claims _claims;

  final SdkVersions _sdks;

  /// [codebase]'s checkout at its pin, resolved, its kept locks read from
  /// [locks].
  ///
  /// The checkout's claim is held from before the survey until the checkout
  /// is handed out, and a git codebase's clone's from before the clone is
  /// touched until the stamp is written, so no other load acts on either
  /// meanwhile, and a load that waited on one finds the checkout standing. A
  /// hosted codebase's takes no claim but its checkout's, and starts no git.
  ///
  /// A checkout that stands is handed out with nothing run but the survey:
  /// a git checkout's status, and the toolchain's version where [_sdks] has
  /// not read it yet. Any other is made again at the pin. A git checkout has
  /// every tracked file's edit reverted and every file the pin lacks
  /// removed, by a checkout and a clean of the worktree where it is one of
  /// the clone's, or is added afresh where it is not. A hosted one is
  /// removed and its package unpacked afresh, with the package around it
  /// written beside it where it resolves as a dependency. Its packages are
  /// then resolved, each on the lock chosen for it, and its stamp written
  /// last, so a make that fails leaves no stamp.
  ///
  /// Throws a [StoreFault] of [Unlocked] where a package has no lock, a git
  /// checkout untouched and a hosted one unpacked, of [PinMissing] where a
  /// clone cannot reach the pin, of [CommandFailed] or [Unstartable] where
  /// git or a toolchain fails, and of [StoreFailed] where a file act does, a
  /// claim's among them.
  Future<Checkout> checkout(Codebase codebase, LocksDirectory locks) =>
      switch (codebase) {
        Git(codebase: final GitCodebase git) => _checkoutGit(git, locks),
        Hosted(codebase: final HostedCodebase hosted) => _checkoutHosted(
          hosted,
          locks,
        ),
      };

  Future<Checkout> _checkoutGit(GitCodebase codebase, LocksDirectory locks) {
    final CheckoutPath at = .of(root, codebase.name);
    return _claims.holding(at.claim, () async {
      final Survey survey = await _survey(Git(codebase), locks, at);
      final Checkout checkout = (
        package: packageIn(at, codebase.root, .root),
        sdk: survey.sdk,
      );
      if (!stands(Git(codebase), survey)) {
        await _claims.holding(
          ClonePath.of(_cache.directory, codebase.url).claim,
          () => _makeGit(codebase, locks, at, survey),
        );
      }
      return checkout;
    });
  }

  Future<Checkout> _checkoutHosted(
    HostedCodebase codebase,
    LocksDirectory locks,
  ) {
    final CheckoutPath at = .of(root, codebase.name);
    return _claims.holding(at.claim, () async {
      final Survey survey = await _survey(Hosted(codebase), locks, at);
      if (!stands(Hosted(codebase), survey)) {
        await _unstamp(at);
        await _resolveAndStamp(
          Hosted(codebase),
          locks,
          at,
          _chosen(
            Hosted(codebase),
            locks,
            chooseLocks(await _unpack(at, codebase), _kept(survey)),
          ),
          survey.sdk,
        );
      }
      return (package: unpackedPackage(at, codebase), sdk: survey.sdk);
    });
  }

  /// The kept locks, in [locks], that [codebase]'s packages lack, each
  /// written from a resolve afresh of its package in the checkout, at the
  /// pin, and moved into place whole, so a write cut short leaves no lock.
  /// A package whose commit holds its lock, or whose kept lock is there, is
  /// left as it is, its lock untouched.
  ///
  /// The claims are a load's: the checkout's held throughout, and a git
  /// codebase's clone's from before the clone is touched until the last lock
  /// is written. Where a lock is written the checkout is made again at the
  /// pin and its stamp deleted first, so the next load makes it again on its
  /// locks. A hosted codebase's packages are read from its checkout where it
  /// stands, and else from its package unpacked afresh, its stamp deleted
  /// first.
  ///
  /// Returns the kept locks written, in [Package]'s order.
  ///
  /// Throws a [StoreFault] of [PinMissing] where a clone cannot reach the
  /// pin, of [CommandFailed] or [Unstartable] where git or a toolchain
  /// fails, and of [StoreFailed] where a file act does, a claim's among them.
  Future<List<KeptLockPath>> lock(Codebase codebase, LocksDirectory locks) =>
      switch (codebase) {
        Git(codebase: final GitCodebase git) => _lockGit(git, locks),
        Hosted(codebase: final HostedCodebase hosted) => _lockHosted(
          hosted,
          locks,
        ),
      };

  Future<List<KeptLockPath>> _lockGit(
    GitCodebase codebase,
    LocksDirectory locks,
  ) {
    final CheckoutPath at = .of(root, codebase.name);
    return _claims.holding(
      at.claim,
      () => _claims.holding(
        ClonePath.of(_cache.directory, codebase.url).claim,
        () async {
          final ClonePath clone = await _cache.clone(
            codebase.url,
            codebase.commit,
          );
          final List<Package> lacking = locksLacking(
            await _atCommit(clone, codebase),
            {
              for (final Package package in Package.values)
                if (await _hash(
                      keptLockOf(locks, Git(codebase), package).path,
                    ) !=
                    null)
                  package,
            },
          );
          if (lacking.isEmpty) {
            return const [];
          }
          await _unstamp(at);
          await _place(at, clone, codebase);
          return _keepLacking(Git(codebase), locks, at, lacking);
        },
      ),
    );
  }

  Future<List<KeptLockPath>> _lockHosted(
    HostedCodebase codebase,
    LocksDirectory locks,
  ) {
    final CheckoutPath at = .of(root, codebase.name);
    return _claims.holding(at.claim, () async {
      final Survey survey = await _survey(Hosted(codebase), locks, at);
      // A checkout that stands resolved every package on its kept lock, so
      // none lacks one.
      if (stands(Hosted(codebase), survey)) {
        return const [];
      }
      await _unstamp(at);
      final List<Package> lacking = locksLacking(
        await _unpack(at, codebase),
        _kept(survey),
      );
      return _keepLacking(Hosted(codebase), locks, at, lacking);
    });
  }

  /// Each of [lacking], [codebase]'s packages in the checkout at [at],
  /// resolved afresh and its lock kept in [locks], in order.
  Future<List<KeptLockPath>> _keepLacking(
    Codebase codebase,
    LocksDirectory locks,
    CheckoutPath at,
    List<Package> lacking,
  ) async {
    final List<KeptLockPath> written = [];
    for (final Package package in lacking) {
      final PackagePath path = packageInCheckout(at, codebase, package);
      // A lock it was served would seed the resolve, which starts from none.
      await removeFile(path.lock.path);
      await _runner.run(codebase.toolchain.lock(path));
      final KeptLockPath kept = keptLockOf(locks, codebase, package);
      await _keep(path, kept);
      written.add(kept);
    }
    return .unmodifiable(written);
  }

  /// The lock [package] resolved to, kept at [kept]: copied to its partial
  /// beside it, then moved into place.
  Future<void> _keep(PackagePath package, KeptLockPath kept) async {
    final PartialLockPath partial = .of(kept);
    await fileAct(
      partial.path,
      () => File(partial.path).create(recursive: true),
    );
    await fileAct(
      package.lock.path,
      () => File(package.lock.path).copy(partial.path),
    );
    await fileAct(partial.path, () => File(partial.path).rename(kept.path));
  }

  /// Deletes the stamp of the checkout at [at], where it is there, so a make
  /// cut short leaves none.
  Future<void> _unstamp(CheckoutPath at) => removeFile(at.stamp.path);

  /// [codebase]'s checkout at [at] made at its pin from its clone, its
  /// packages resolved on their locks and its stamp written last, the
  /// [survey] read of it before.
  Future<void> _makeGit(
    GitCodebase codebase,
    LocksDirectory locks,
    CheckoutPath at,
    Survey survey,
  ) async {
    final ClonePath clone = await _cache.clone(codebase.url, codebase.commit);
    final Map<Package, LockSource> chosen = _chosen(
      Git(codebase),
      locks,
      chooseLocks(await _atCommit(clone, codebase), _kept(survey)),
    );
    await _unstamp(at);
    await _place(at, clone, codebase);
    await _resolveAndStamp(Git(codebase), locks, at, chosen, survey.sdk);
  }

  /// The lock each package resolves on in [choice], or a [StoreFault] of
  /// [Unlocked] thrown, naming the kept lock in [locks] of [codebase]'s
  /// package that has none.
  Map<Package, LockSource> _chosen(
    Codebase codebase,
    LocksDirectory locks,
    LockChoice choice,
  ) => switch (choice) {
    LocksChosen(:final Map<Package, LockSource> locks) => locks,
    LockLacking(:final Package package) => throw StoreFault(
      Unlocked(keptLockOf(locks, codebase, package)),
    ),
  };

  /// The packages [survey] found a kept lock for.
  Set<Package> _kept(Survey survey) => {
    for (final MapEntry<Package, SurveyedPackage>(:key, :value)
        in survey.packages.entries)
      if (value.keptLock != null) key,
  };

  /// [codebase]'s packages in the checkout at [at], each with the lock
  /// [chosen] for it in place, resolved by [sdk]'s toolchain, and the stamp
  /// written last.
  Future<void> _resolveAndStamp(
    Codebase codebase,
    LocksDirectory locks,
    CheckoutPath at,
    Map<Package, LockSource> chosen,
    SdkVersion sdk,
  ) async {
    // Every lock is in place before any package resolves, so no resolve
    // meets a package still lacking its lock.
    for (final MapEntry<Package, LockSource>(key: package, value: source)
        in chosen.entries) {
      switch (source) {
        case .committed:
          break;
        case .kept:
          final KeptLockPath kept = keptLockOf(locks, codebase, package);
          await fileAct(
            kept.path,
            () =>
                File(kept.path)
                    .copy(packageInCheckout(at, codebase, package).lock.path),
          );
      }
    }
    final Map<Package, StampedPackage> packages = {};
    for (final MapEntry<Package, LockSource>(key: package, value: source)
        in chosen.entries) {
      packages[package] = await _resolve(
        codebase,
        packageInCheckout(at, codebase, package),
        source,
      );
    }
    final Stamp stamp = (
      codebase: codebase,
      packages: .unmodifiable(packages),
      sdk: sdk,
    );
    await fileAct(
      at.stamp.path,
      () => File(at.stamp.path).writeAsString(renderStamp(stamp)),
    );
  }

  /// [codebase]'s package unpacked afresh into the checkout at [at],
  /// whatever stood there removed first, and the package around it written
  /// in the checkout's top where it resolves as a dependency, each package's
  /// overrides written where it needs them to resolve alone and holds none,
  /// and what it
  /// holds of its packages: the root always, and the example where it holds
  /// a pubspec of its own.
  Future<AtCommit> _unpack(CheckoutPath at, HostedCodebase codebase) async {
    await removeDirectory(at.path);
    await fileAct(at.path, () => Directory(at.path).create(recursive: true));
    await _runner.run(unpackCommand(codebase, at));
    switch (codebase.resolution) {
      case .alone:
        break;
      case .asDependency:
        final PubspecPath around = hostedPackage(at, codebase, .root).pubspec;
        await fileAct(
          around.path,
          () => File(around.path).writeAsString(aroundPubspec(codebase)),
        );
    }
    final Set<Package> packages = {};
    for (final Package package in Package.values) {
      // The root's own pubspec, under either resolution, since the package
      // around it is muster's.
      final PubspecPath pubspec = switch (package) {
        .root => unpackedPackage(at, codebase).pubspec,
        .example => hostedPackage(at, codebase, package).pubspec,
      };
      final List<int>? bytes = await bytesIfThere(pubspec.path);
      if (!hostedResolves(package, held: bytes != null)) {
        continue;
      }
      packages.add(package);
      final PubspecOverridesPath path = hostedPackage(
        at,
        codebase,
        package,
      ).overrides;
      if (pubspecOverrides(
            codebase,
            package,
            member: switch (bytes) {
              final List<int> bytes => workspaceMember(
                utf8.decode(bytes, allowMalformed: true),
              ),
              null => false,
            },
            holding: await bytesIfThere(path.path) != null,
          )
          case final String overrides) {
        await fileAct(
          path.path,
          () => File(path.path).writeAsString(overrides),
        );
      }
    }
    return (packages: packages, locked: const <Package>{});
  }

  /// The survey of [codebase]'s checkout at [at], its kept locks in [locks].
  /// Its packages are read only where a directory stands at [at], so
  /// anything else there, a file among them, reads as no checkout. Git reads
  /// a git checkout only where a stamp is there to weigh it against, and
  /// never a hosted one.
  Future<Survey> _survey(
    Codebase codebase,
    LocksDirectory locks,
    CheckoutPath at,
  ) async {
    final SdkVersion sdk = await _sdks.of(codebase.toolchain);
    final Stamp? stamp = switch (await bytesIfThere(at.stamp.path)) {
      final List<int> bytes => parseStamp(
        utf8.decode(bytes, allowMalformed: true),
      ),
      null => null,
    };
    final bool there = await _there(at);
    final Worktree? worktree = switch (codebase) {
      Git() when stamp != null && there => await _status(at),
      Git() || Hosted() => null,
    };
    final Map<Package, SurveyedPackage> packages = {};
    for (final Package package in Package.values) {
      final PackagePath path = packageInCheckout(at, codebase, package);
      packages[package] = (
        lock: there ? await _hash(path.lock.path) : null,
        keptLock: await _hash(keptLockOf(locks, codebase, package).path),
        packageConfig: there ? await _hash(path.packageConfig.path) : null,
      );
    }
    final PubspecPath handedOut = switch (codebase) {
      Git(codebase: final GitCodebase git) => packageIn(
        at,
        git.root,
        .root,
      ).pubspec,
      Hosted(codebase: final HostedCodebase hosted) => unpackedPackage(
        at,
        hosted,
      ).pubspec,
    };
    final Survey survey = (
      sdk: sdk,
      stamp: stamp,
      worktree: worktree,
      there:
          there && await fileAct(handedOut.path, File(handedOut.path).exists),
      packages: .unmodifiable(packages),
    );
    return survey;
  }

  /// The worktree at [at] as git reads it, or null where git finds no
  /// worktree there.
  Future<Worktree?> _status(CheckoutPath at) async {
    final Ran ran = await _runner.run(
      gitIn(at, [
        '--no-optional-locks',
        'status',
        '--porcelain=v2',
        '--branch',
        '-z',
        '--untracked-files=no',
      ]),
      exits: const {0, _notARepo},
    );
    return ran.exitCode == 0 ? readStatus(ran.stdout) : null;
  }

  /// What [codebase]'s commit holds of its packages, read from [clone].
  Future<AtCommit> _atCommit(ClonePath clone, GitCodebase codebase) async {
    final Ran ran = await _runner.run(
      gitOn(clone, [
        '--literal-pathspecs',
        'ls-tree',
        '-z',
        '--name-only',
        codebase.commit.hash,
        '--',
        for (final RepoPath file in atCommitFiles(codebase.root)) file.path,
      ]),
    );
    return readAtCommit(codebase.root, {
      for (final String file in ran.stdout.split('\x00'))
        if (file.isNotEmpty) .listed(file),
    });
  }

  /// [codebase]'s checkout at [at] made at its pin, holding the pin's
  /// tracked files alone: a worktree of [clone] there checked out by force
  /// and cleaned, and anything else there removed and added afresh, the
  /// clone's worktrees pruned first, so one deleted by hand never blocks it.
  Future<void> _place(
    CheckoutPath at,
    ClonePath clone,
    GitCodebase codebase,
  ) async {
    switch (chooseCheckoutStep(await _found(at, clone))) {
      case .move:
        await moveWorktree(_runner, at, codebase.commit);
      case .replace:
        await removeDirectory(at.path);
        await fileAct(
          at.path,
          () => Directory(at.os.paths.dirname(at.path)).create(recursive: true),
        );
        await addWorktree(_runner, clone, at, codebase.commit);
    }
  }

  /// What stands at [at], read against [clone].
  Future<CheckoutFound> _found(CheckoutPath at, ClonePath clone) async {
    if (!await _there(at)) {
      return .nothing;
    }
    return await _worktreeOf(at, clone) ? .worktreeOfClone : .other;
  }

  /// Whether the directory at [at] is a worktree of [clone].
  Future<bool> _worktreeOf(CheckoutPath at, ClonePath clone) async {
    final Ran ran = await _runner.run(
      gitIn(at, ['rev-parse', '--path-format=absolute', '--git-common-dir']),
      exits: const {0, _notARepo},
    );
    if (ran.exitCode != 0) {
      return false;
    }
    final String common = ran.stdout.trim();
    return fileAct(clone.path, () async {
      if (!await Directory(common).exists()) {
        return false;
      }
      return at.os.paths.equals(
        await Directory(common).resolveSymbolicLinks(),
        await Directory(clone.path).resolveSymbolicLinks(),
      );
    });
  }

  /// [package] resolved by [codebase]'s toolchain on the lock placed in it,
  /// which came from [source], and what its stamp records of it.
  Future<StampedPackage> _resolve(
    Codebase codebase,
    PackagePath package,
    LockSource source,
  ) async {
    final String lock = package.lock.path;
    await _runner.run(codebase.toolchain.resolve(package));
    final String config = package.packageConfig.path;
    return (
      source: source,
      lock: ContentHash.of(await fileAct(lock, File(lock).readAsBytes)),
      packageConfig: ContentHash.of(
        await fileAct(config, File(config).readAsBytes),
      ),
    );
  }

  /// The hash of the file at [path], or null where nothing is there.
  Future<ContentHash?> _hash(String path) async =>
      switch (await bytesIfThere(path)) {
        final List<int> bytes => .of(bytes),
        null => null,
      };

  /// Whether a directory stands at [at].
  Future<bool> _there(CheckoutPath at) =>
      fileAct(at.path, Directory(at.path).exists);
}

/// The code git exits with where it finds no repo it can read.
const int _notARepo = 128;

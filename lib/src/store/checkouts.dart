import 'dart:convert';
import 'dart:io';

import '../model/at_commit.dart';
import '../model/checkout.dart';
import '../model/checkout_path.dart';
import '../model/choose_locks.dart';
import '../model/at_commit_files.dart';
import '../model/clone_path.dart';
import '../model/command.dart';
import '../model/consumer_root.dart';
import '../model/content_hash.dart';
import '../model/fetch_outcome.dart';
import '../model/git_codebase.dart';
import '../model/kept_lock_path.dart';
import '../model/lock_choice.dart';
import '../model/lock_source.dart';
import '../model/locks_directory.dart';
import '../model/locks_lacking.dart';
import '../model/package.dart';
import '../model/package_path.dart';
import '../model/parse_stamp.dart';
import '../model/partial_lock_path.dart';
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
import '../model/toolchain.dart';
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
import 'runner.dart';
import 'store_fault.dart';

/// A consumer's checkouts, one a git codebase under its root, each a worktree
/// of the codebase's clone in a [Cache], its processes run by a [Runner] and
/// its acts held under [Claims].
class Checkouts {
  /// The checkouts under [root], cloned into [_cache], their git and
  /// toolchains run by [_runner], each acted on under its claim in
  /// [_claims].
  Checkouts(this.root, this._cache, this._runner, this._claims);

  /// The consumer's root, the checkouts under its `.dart_tool/muster/`.
  final ConsumerRoot root;

  final Cache _cache;

  final Runner _runner;

  final Claims _claims;

  /// [codebase]'s checkout at its pin, resolved, its kept locks read from
  /// [locks].
  ///
  /// The checkout's claim is held from before the survey until the checkout
  /// is handed out, and the clone's from before the clone is touched until
  /// the stamp is written, so no other load acts on either meanwhile, and a
  /// load that waited on one finds the checkout standing.
  ///
  /// A checkout that stands is handed out with nothing run but the survey:
  /// the toolchain's version and the checkout's git status. Any other is
  /// made again at the pin, every tracked file's edit reverted and every file
  /// the pin lacks removed, by a checkout and a clean of the worktree where it
  /// is one of the clone's, or added afresh where it is not. Its packages are
  /// then resolved, each on the lock chosen for it, and its stamp written
  /// last, so a make that fails leaves no stamp.
  ///
  /// Throws a [StoreFault] of [Unlocked] where a package has no lock, with
  /// the checkout untouched, of [PinMissing] where the clone cannot reach the
  /// pin, of [CommandFailed] or [Unstartable] where git or the toolchain
  /// fails, and of [StoreFailed] where a file act does, a claim's among them.
  Future<Checkout> checkout(GitCodebase codebase, LocksDirectory locks) {
    final CheckoutPath at = .of(root, codebase.name);
    return _claims.holding(at.claim, () async {
      final Survey survey = await _survey(codebase, locks, at);
      final Checkout checkout = (
        package: .of(at, codebase.root, .root),
        sdk: survey.sdk,
      );
      if (!stands(codebase, survey)) {
        await _claims.holding(
          ClonePath.of(_cache.directory, codebase.url).claim,
          () => _make(codebase, locks, at, survey),
        );
      }
      return checkout;
    });
  }

  /// The kept locks, in [locks], that [codebase]'s packages lack, each
  /// written from a resolve afresh of its package in the checkout, at the
  /// pin, and moved into place whole, so a write cut short leaves no lock.
  /// A package whose commit holds its lock, or whose kept lock is there, is
  /// left as it is, its lock untouched.
  ///
  /// The claims are a load's: the checkout's held throughout, and the
  /// clone's from before the clone is touched until the last lock is
  /// written. Where a lock is written the checkout is made again at the pin
  /// and its stamp deleted first, so the next load makes it again on its
  /// locks.
  ///
  /// Returns the kept locks written, in [Package]'s order.
  ///
  /// Throws a [StoreFault] of [PinMissing] where the clone cannot reach the
  /// pin, of [CommandFailed] or [Unstartable] where git or the toolchain
  /// fails, and of [StoreFailed] where a file act does, a claim's among them.
  Future<List<KeptLockPath>> lock(GitCodebase codebase, LocksDirectory locks) {
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
                      KeptLockPath.of(locks, codebase, package).path,
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
          final List<KeptLockPath> written = [];
          for (final Package package in lacking) {
            final PackagePath path = .of(at, codebase.root, package);
            await _runner.run(codebase.toolchain.lock(path));
            final KeptLockPath kept = .of(locks, codebase, package);
            await _keep(path, kept);
            written.add(kept);
          }
          return .unmodifiable(written);
        },
      ),
    );
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
  Future<void> _unstamp(CheckoutPath at) => fileAct(at.stamp.path, () async {
    if (await File(at.stamp.path).exists()) {
      await File(at.stamp.path).delete();
    }
  });

  /// [codebase]'s checkout at [at] made at its pin from its clone, its
  /// packages resolved on their locks and its stamp written last, the
  /// [survey] read of it before.
  Future<void> _make(
    GitCodebase codebase,
    LocksDirectory locks,
    CheckoutPath at,
    Survey survey,
  ) async {
    final ClonePath clone = await _cache.clone(codebase.url, codebase.commit);
    final Map<Package, LockSource> chosen = switch (chooseLocks(
      await _atCommit(clone, codebase),
      {
        for (final MapEntry<Package, SurveyedPackage>(:key, :value)
            in survey.packages.entries)
          if (value.keptLock != null) key,
      },
    )) {
      LocksChosen(:final Map<Package, LockSource> locks) => locks,
      LockLacking(:final Package package) => throw StoreFault(
        Unlocked(.of(locks, codebase, package)),
      ),
    };
    await _unstamp(at);
    await _place(at, clone, codebase);
    // Every lock is in place before any package resolves, so no resolve
    // meets a package still lacking its lock.
    for (final MapEntry<Package, LockSource>(key: package, value: source)
        in chosen.entries) {
      switch (source) {
        case .committed:
          break;
        case .kept:
          final KeptLockPath kept = .of(locks, codebase, package);
          await fileAct(
            kept.path,
            () =>
                File(kept.path)
                    .copy(PackagePath.of(at, codebase.root, package).lock.path),
          );
      }
    }
    final Map<Package, StampedPackage> packages = {};
    for (final MapEntry<Package, LockSource>(key: package, value: source)
        in chosen.entries) {
      packages[package] = await _resolve(
        codebase,
        .of(at, codebase.root, package),
        source,
      );
    }
    final Stamp stamp = (
      url: codebase.url,
      commit: codebase.commit,
      root: codebase.root,
      toolchain: codebase.toolchain,
      packages: .unmodifiable(packages),
      sdk: survey.sdk,
    );
    await fileAct(
      at.stamp.path,
      () => File(at.stamp.path).writeAsString(renderStamp(stamp)),
    );
  }

  /// The survey of [codebase]'s checkout at [at], its kept locks in [locks].
  /// Git reads the worktree only where a stamp is there to weigh it against.
  Future<Survey> _survey(
    GitCodebase codebase,
    LocksDirectory locks,
    CheckoutPath at,
  ) async {
    final SdkVersion sdk = await _version(codebase.toolchain);
    final Stamp? stamp = switch (await bytesIfThere(at.stamp.path)) {
      final List<int> bytes => parseStamp(
        utf8.decode(bytes, allowMalformed: true),
      ),
      null => null,
    };
    final Worktree? worktree = stamp != null && await _there(at)
        ? await _status(at)
        : null;
    final Map<Package, SurveyedPackage> packages = {};
    for (final Package package in Package.values) {
      final PackagePath path = .of(at, codebase.root, package);
      packages[package] = (
        lock: await _hash(path.lock.path),
        keptLock: await _hash(KeptLockPath.of(locks, codebase, package).path),
        packageConfig: await _hash(path.packageConfig.path),
      );
    }
    final Survey survey = (
      sdk: sdk,
      stamp: stamp,
      worktree: worktree,
      packages: .unmodifiable(packages),
    );
    return survey;
  }

  /// The version of [toolchain]'s SDK on `PATH`.
  Future<SdkVersion> _version(Toolchain toolchain) async {
    final Command command = toolchain.version;
    final Ran ran = await _runner.run(command);
    return .read(toolchain, ran.stdout) ??
        (throw StoreFault(
          CommandFailed(command, ran.exitCode, ran.stdout, ran.stderr),
        ));
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
    if (await _there(at)) {
      if (await _worktreeOf(at, clone)) {
        await moveWorktree(_runner, at, codebase.commit);
        return;
      }
      await fileAct(at.path, () => Directory(at.path).delete(recursive: true));
    }
    await fileAct(
      at.path,
      () => Directory(at.os.paths.dirname(at.path)).create(recursive: true),
    );
    await addWorktree(_runner, clone, at, codebase.commit);
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
    GitCodebase codebase,
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

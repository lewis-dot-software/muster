import 'dart:convert';

import '../model/cache_directory.dart';
import '../model/codebase.dart';
import '../model/checkout.dart';
import '../model/consumer_root.dart';
import '../model/environment.dart';
import '../model/codebase_name.dart';
import '../model/fetch_outcome.dart';
import '../model/git_codebase.dart';
import '../model/kept_lock_path.dart';
import '../model/load_refusal.dart';
import '../model/lock_outcome.dart';
import '../model/lock_removal.dart';
import '../model/locks_directory.dart';
import '../model/manifest.dart';
import '../model/manifest_merge.dart';
import '../model/manifest_parse.dart';
import '../model/manifest_path.dart';
import '../model/manifest_refusal.dart';
import '../model/manifest_sought.dart';
import '../model/merge_manifests.dart';
import '../model/named_codebase.dart';
import '../model/parse_manifest.dart';
import '../model/partial_lock_path.dart';
import '../model/seek_manifests.dart';
import '../model/temp_directory.dart';
import '../model/unnamed_lock.dart';
import '../model/choose_unnamed.dart';
import '../model/working_directory.dart';
import '../store/bytes_if_there.dart';
import '../store/cache.dart';
import '../store/checkouts.dart';
import '../store/claims.dart';
import '../store/names_in.dart';
import '../store/remove_file.dart';
import '../store/runner.dart';
import '../store/sdk_versions.dart';
import '../store/store_fault.dart';
import 'load.dart';
import 'loads.dart';
import 'locking.dart';
import 'muster.dart';

/// Loads the codebases a consumer's manifests name, in the environment and
/// working directory it was made with, its processes run by a [Runner] and
/// its acts on clones and checkouts held under [Claims].
class Loader implements Loads {
  /// The loader that reads [_environment] and resolves relative paths
  /// against [_workingDirectory], its git and toolchains run by [_runner],
  /// each clone and checkout acted on under its claim in [_claims], and the
  /// scratches of what it loads made under [_temp].
  Loader(
    this._environment,
    this._workingDirectory,
    this._runner,
    this._claims,
    this._temp,
  );

  final Environment _environment;

  final WorkingDirectory _workingDirectory;

  final Runner _runner;

  final Claims _claims;

  final TempDirectory _temp;

  /// Reads the manifests, the [named] ones where any is given and else the
  /// `muster.yaml` at [root] and every one `MUSTER_MANIFESTS` lists, then
  /// brings each codebase they name to its pin in a checkout under [root],
  /// the working directory where it is left out, one after another in the
  /// manifests' order.
  ///
  /// Refuses, with no process started and no file written, on the first
  /// fault the manifests meet: a manifest whose file name does not end
  /// `.yaml`, one named that is missing, unreadable or refuses to parse, a
  /// load with no manifest at all, a name met twice, a hosted codebase, or no
  /// cache.
  ///
  /// Every expected failure a codebase meets is its outcome, and the load
  /// goes on to the next. Another load acting on a codebase's clone or
  /// checkout is waited on, never acted beside. The [Loaded] carries the
  /// [Muster] that makes a scratch of each codebase the manifests name.
  @override
  Future<Load> load({List<String> named = const [], String? root}) async {
    final _Read read;
    try {
      read = await _read(named, root);
    } on _Refusal catch (refusal) {
      return Refused(refusal.reason);
    }
    final Map<CodebaseName, FetchOutcome> outcomes = {};
    for (final (:codebase, :manifest) in read.codebases) {
      try {
        final Checkout checkout = await read.checkouts.checkout(
          codebase,
          .beside(read.manifests[manifest]),
        );
        outcomes[codebase.name] = Fetched(checkout.package, checkout.sdk);
      } on StoreFault catch (fault) {
        outcomes[codebase.name] = fault.failure;
      }
    }
    final Muster muster = .new(
      .unmodifiable(<CodebaseName, GitCodebase>{
        for (final (:codebase, manifest: _) in read.codebases)
          codebase.name: codebase,
      }),
      .new(read.clones, _runner, _claims, _temp),
    );
    return Loaded(muster, .unmodifiable(outcomes));
  }

  /// Reads the manifests as [load] does, the working directory the root,
  /// then writes each kept lock a codebase they name needs and lacks, from a
  /// resolve afresh of its package in its checkout, one codebase after
  /// another in the
  /// manifests' order. Every lock that is there is left untouched.
  ///
  /// Then removes, from each manifest's locks, every kept lock no codebase
  /// of that manifest names, and every partial of a write cut short that
  /// none names, so a run right after it writes and removes nothing. A file
  /// there that is neither is left.
  ///
  /// Refuses as [load] does, with no process started and no file written.
  ///
  /// Every expected failure a codebase's write meets is its outcome, and
  /// every removal's is its own, and the run goes on to the next. Another
  /// load or lock acting on a codebase's clone or checkout is waited on,
  /// never acted beside.
  @override
  Future<Locking> lock({List<String> named = const []}) async {
    final _Read read;
    try {
      read = await _read(named, null);
    } on _Refusal catch (refusal) {
      return LockRefused(refusal.reason);
    }
    final Map<CodebaseName, LockOutcome> outcomes = {};
    for (final (:codebase, :manifest) in read.codebases) {
      try {
        outcomes[codebase.name] = LocksWritten(
          await read.checkouts.lock(
            codebase,
            .beside(read.manifests[manifest]),
          ),
        );
      } on StoreFault catch (fault) {
        outcomes[codebase.name] = LockFailed(fault.act);
      }
    }
    final List<LockRemoval> removals = [];
    for (final (int index, ManifestPath manifest) in read.manifests.indexed) {
      removals.addAll(
        await _removeUnnamed(.beside(manifest), [
          for (final (:codebase, manifest: int at) in read.codebases)
            if (at == index) codebase,
        ]),
      );
    }
    return Locked(.unmodifiable(outcomes), .unmodifiable(removals));
  }

  /// Removes from [locks] what no codebase of [codebases] names, in its file
  /// names' order, each kept lock's removal given as its own, and a
  /// partial's only where it fails.
  Future<List<LockRemoval>> _removeUnnamed(
    LocksDirectory locks,
    List<GitCodebase> codebases,
  ) async {
    final List<String> names;
    try {
      names = await namesIn(locks);
    } on StoreFault catch (fault) {
      return [RemovalFailed(fault.fileFailure)];
    }
    final List<LockRemoval> removals = [];
    for (final UnnamedLock unnamed in chooseUnnamed(locks, names, codebases)) {
      try {
        switch (unnamed) {
          case UnnamedKept(:final KeptLockPath lock):
            await removeFile(lock.path);
            removals.add(LockRemoved(lock));
          case UnnamedPartial(:final PartialLockPath partial):
            await removeFile(partial.path);
        }
      } on StoreFault catch (fault) {
        removals.add(RemovalFailed(fault.fileFailure));
      }
    }
    return removals;
  }

  /// What the manifests [named], or else the `muster.yaml` at [root] and
  /// every one `MUSTER_MANIFESTS` lists, name, in their order, beside the
  /// checkouts under [root] that bring them to their pins.
  ///
  /// Throws a [_Refusal] on the first fault the manifests meet, or where no
  /// cache is named, with no process started and no file written.
  Future<_Read> _read(List<String> named, String? root) async {
    final ConsumerRoot consumer = .new(
      _workingDirectory.resolve(root ?? '.'),
      _environment.os,
    );
    final List<ManifestPath> paths = [];
    final List<Manifest> manifests = [];
    for (final ManifestSought sought in seekManifests(
      named,
      _environment,
      consumer,
      _workingDirectory,
    )) {
      final ManifestPath? manifest = .parse(sought.path, _environment.os);
      if (manifest == null) {
        throw _Refusal(NotManifestName(sought.path));
      }
      final List<int>? bytes;
      try {
        bytes = await bytesIfThere(manifest.path);
      } on StoreFault catch (fault) {
        throw _Refusal(ManifestUnreadable(manifest, fault.fileFailure.reason));
      }
      if (bytes == null) {
        if (sought.named) {
          throw _Refusal(ManifestMissing(manifest));
        }
        continue;
      }
      final String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException catch (e) {
        throw _Refusal(
          ManifestInvalid(
            manifest,
            NotYaml(switch (e.offset) {
              final int offset => 'byte $offset: ${e.message}',
              null => e.message,
            }),
          ),
        );
      }
      switch (parseManifest(text)) {
        case ManifestParsed(:final Manifest manifest):
          manifests.add(manifest);
        case ManifestRefused(:final ManifestRefusal refusal):
          throw _Refusal(ManifestInvalid(manifest, refusal));
      }
      paths.add(manifest);
    }
    if (manifests.isEmpty) {
      throw const _Refusal(NoManifest());
    }
    final List<_NamedGit> codebases;
    switch (mergeManifests(manifests)) {
      case Merged(codebases: final List<NamedCodebase> merged):
        codebases = [
          for (final (:Codebase codebase, :int manifest) in merged)
            switch (codebase) {
              Git(codebase: final GitCodebase git) => (
                codebase: git,
                manifest: manifest,
              ),
              Hosted(:final CodebaseName name) => throw _Refusal(
                HostedNotLoaded(paths[manifest], name),
              ),
            },
        ];
      case NamedTwice(
        :final CodebaseName name,
        :final int first,
        :final int second,
      ):
        throw _Refusal(
          CodebaseNamedTwice(name, first: paths[first], second: paths[second]),
        );
    }
    final CacheDirectory? cache = .of(_environment);
    if (cache == null) {
      throw _Refusal(NoCache(_environment.os));
    }
    final Cache clones = .new(cache, _runner, _claims);
    return (
      manifests: List<ManifestPath>.unmodifiable(paths),
      codebases: codebases,
      clones: clones,
      checkouts: Checkouts(
        consumer,
        clones,
        _runner,
        _claims,
        SdkVersions(_runner),
      ),
    );
  }
}

/// What a run read before it acts: the [manifests] read, in order, the
/// [codebases] they name, each beside its manifest's index among them, the
/// [clones] in the cache, and the [checkouts] that bring them to their pins.
typedef _Read = ({
  List<ManifestPath> manifests,
  List<_NamedGit> codebases,
  Cache clones,
  Checkouts checkouts,
});

/// A git codebase beside the index of the manifest that named it among the
/// load's.
typedef _NamedGit = ({GitCodebase codebase, int manifest});

/// A run refused for [reason] before any process or file write.
final class _Refusal implements Exception {
  const _Refusal(this.reason);

  final LoadRefusal reason;
}

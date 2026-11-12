import 'dart:convert';

import '../model/cache_directory.dart';
import '../model/checkout.dart';
import '../model/consumer_root.dart';
import '../model/environment.dart';
import '../model/codebase_name.dart';
import '../model/fetch_outcome.dart';
import '../model/load_refusal.dart';
import '../model/manifest.dart';
import '../model/manifest_merge.dart';
import '../model/manifest_parse.dart';
import '../model/manifest_path.dart';
import '../model/manifest_refusal.dart';
import '../model/manifest_sought.dart';
import '../model/merge_manifests.dart';
import '../model/named_codebase.dart';
import '../model/parse_manifest.dart';
import '../model/seek_manifests.dart';
import '../model/working_directory.dart';
import '../store/bytes_if_there.dart';
import '../store/checkouts.dart';
import '../store/claims.dart';
import '../store/runner.dart';
import '../store/store_fault.dart';
import 'load.dart';

/// Loads the codebases a consumer's manifests name, in the environment and
/// working directory it was made with, its processes run by a [Runner] and
/// its acts on clones and checkouts held under [Claims].
class Loader {
  /// The loader that reads [_environment] and resolves relative paths
  /// against [_workingDirectory], its git and toolchains run by [_runner],
  /// each clone and checkout acted on under its claim in [_claims].
  Loader(this._environment, this._workingDirectory, this._runner, this._claims);

  final Environment _environment;

  final WorkingDirectory _workingDirectory;

  final Runner _runner;

  final Claims _claims;

  /// Reads the manifests, the [named] ones where any is given and else the
  /// `muster.yaml` at [root] and every one `MUSTER_MANIFESTS` lists, then
  /// brings each codebase they name to its pin in a checkout under [root],
  /// the working directory where it is left out, one after another in the
  /// manifests' order.
  ///
  /// Refuses, with no process started and no file written, on the first
  /// fault the manifests meet: a manifest whose file name does not end
  /// `.yaml`, one named that is missing, unreadable or refuses to parse, a
  /// load with no manifest at all, a name met twice, or no cache.
  ///
  /// Every expected failure a codebase meets is its outcome, and the load
  /// goes on to the next. Another load acting on a codebase's clone or
  /// checkout is waited on, never acted beside.
  Future<Load> load({List<String> named = const [], String? root}) async {
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
        return Refused(NotManifestName(sought.path));
      }
      final List<int>? bytes;
      try {
        bytes = await bytesIfThere(manifest.path);
      } on StoreFault catch (fault) {
        if (fault.failure case StoreFailed(:final String reason)) {
          return Refused(ManifestUnreadable(manifest, reason));
        }
        rethrow;
      }
      if (bytes == null) {
        if (sought.named) {
          return Refused(ManifestMissing(manifest));
        }
        continue;
      }
      final String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException catch (e) {
        return Refused(ManifestInvalid(manifest, NotYaml('$e')));
      }
      switch (parseManifest(text)) {
        case ManifestParsed(:final Manifest manifest):
          manifests.add(manifest);
        case ManifestRefused(:final ManifestRefusal refusal):
          return Refused(ManifestInvalid(manifest, refusal));
      }
      paths.add(manifest);
    }
    if (manifests.isEmpty) {
      return const Refused(NoManifest());
    }
    final List<NamedCodebase> codebases;
    switch (mergeManifests(manifests)) {
      case Merged(codebases: final List<NamedCodebase> merged):
        codebases = merged;
      case NamedTwice(
        :final CodebaseName name,
        :final int first,
        :final int second,
      ):
        return Refused(
          CodebaseNamedTwice(name, first: paths[first], second: paths[second]),
        );
    }
    final CacheDirectory? cache = .of(_environment);
    if (cache == null) {
      return const Refused(NoCache());
    }
    final Checkouts checkouts = .new(
      consumer,
      .new(cache, _runner),
      _runner,
      _claims,
    );
    final Map<CodebaseName, FetchOutcome> outcomes = {};
    for (final (:codebase, :manifest) in codebases) {
      try {
        final Checkout checkout = await checkouts.checkout(
          codebase,
          .beside(paths[manifest]),
        );
        outcomes[codebase.name] = Fetched(checkout.package, checkout.sdk);
      } on StoreFault catch (fault) {
        outcomes[codebase.name] = fault.failure;
      }
    }
    return Loaded(.unmodifiable(outcomes));
  }
}

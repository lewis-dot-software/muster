import 'dart:io';

import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/git_url.dart';
import 'package:muster/src/store/ran.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;

/// The hash an origin names its objects by, each by git's own name for it.
enum OriginFormat {
  /// SHA-1.
  sha1,

  /// SHA-256.
  sha256,
}

/// A bare repo a test makes, cloned from by its path, its default branch
/// `main`.
class Origin {
  Origin._(this.directory, this._runner, this._tree);

  /// The repo made in `origin` under [parent], in [format], its git run by
  /// [runner].
  static Future<Origin> make(
    Directory parent,
    Runner runner, {
    OriginFormat format = .sha1,
  }) async {
    final Directory directory = await .new(
      p.join(parent.path, 'origin'),
    ).create();
    await runner.run((
      executable: .git,
      arguments: [
        'init',
        '--quiet',
        '--bare',
        '--initial-branch=main',
        '--object-format=${format.name}',
        directory.path,
      ],
    ));
    final Ran tree = await runner.run((
      executable: .git,
      arguments: [
        '--git-dir=${directory.path}',
        'hash-object',
        '-w',
        '-t',
        'tree',
        '/dev/null',
      ],
    ));
    return ._(directory, runner, tree.stdout.trim());
  }

  /// The repo's directory.
  final Directory directory;

  final Runner _runner;

  /// The empty tree's hash, which every commit made here holds.
  final String _tree;

  int _made = 0;

  /// The URL the repo is cloned from.
  GitUrl get url => .parse(directory.path)!;

  /// A new commit, its parent [parent] where one is given, and none where it
  /// is not.
  Future<Commit> commit([Commit? parent]) async {
    final Ran ran = await _git([
      'commit-tree',
      _tree,
      if (parent != null) ...['-p', parent.hash],
      '-m',
      'commit ${_made++}',
    ]);
    return .parse(ran.stdout.trim())!;
  }

  /// Sets the ref [name], `refs/heads/main` as one is, at [commit].
  Future<void> ref(String name, Commit commit) =>
      _git(['update-ref', name, commit.hash]);

  /// Deletes the ref [name].
  Future<void> delete(String name) => _git(['update-ref', '-d', name]);

  /// Tags [commit] [name], an annotated tag where [annotated] holds.
  Future<void> tag(String name, Commit commit, {required bool annotated}) =>
      _git([
        'tag',
        if (annotated) ...['-a', '-m', name],
        name,
        commit.hash,
      ]);

  /// The commit or tag object [ref] names.
  Future<String> resolve(String ref) async =>
      (await _git(['rev-parse', ref])).stdout.trim();

  Future<Ran> _git(List<String> arguments) => _runner.run((
    executable: .git,
    arguments: ['--git-dir=${directory.path}', ...arguments],
  ));
}

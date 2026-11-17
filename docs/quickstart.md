---
type: knowledge
aliases: getting started, install, first load, tutorial, user guide
---

# Quickstart

This page installs muster in a package, names two codebases for its tests, and loads them in a test, writing their locks on the way, then links a doc for each topic it touches. A codebase is a real package a tool is tested against, named by a git repo at a commit or by a package on pub.dev at a version, and muster brings each to that pin, resolved, inside the test.

## Install

muster runs inside `package:test` on the Dart VM, from Dart 3.13, with `git` on `PATH`. Until `v1.0.0` reaches pub.dev, a package pins a tag of muster's public repo as a dev dependency:

```yaml
dev_dependencies:
  muster:
    git:
      url: https://github.com/lewis-dot-software/muster
      ref: v0.2.1
  test: ^1.33.0
```

Then `dart pub get`.

## Name the codebases

`muster.yaml` at the package's root names each codebase by its key. This one pins equatable's repo at its `v3.0.0` commit, and `path` from pub.dev at `1.9.1`, each resolved by `dart`:

```yaml
codebases:
  equatable:
    git: https://github.com/felangel/equatable.git
    commit: 272ff7e97642dacba8f1d6e6c20ab8d6d68e5c4c
    toolchain: dart
  path:
    hosted: path
    version: 1.9.1
    toolchain: dart
```

## Write the test

In `test/codebases_test.dart`:

```dart
import 'dart:io';

import 'package:muster/muster.dart';
import 'package:test/test.dart';

void main() {
  test('every codebase muster.yaml names loads at its pin, resolved', () async {
    switch (await Muster.load()) {
      case Refused(:final LoadRefusal reason):
        fail('The load refused: $reason');
      case Loaded(:final Map<CodebaseName, FetchOutcome> outcomes):
        for (final MapEntry(key: CodebaseName name, value: FetchOutcome outcome)
            in outcomes.entries) {
          switch (outcome) {
            case Fetched(:final PackagePath package, :final SdkVersion sdk):
              // Hand package.path to the tool under test.
              expect(File(package.packageConfig.path).existsSync(), isTrue);
              print('${name.name} at ${package.path}, resolved by $sdk');
            case Unlocked(:final KeptLockPath lock):
              fail(
                '${name.name} has no lock: run `dart run muster lock` '
                'to write ${lock.path}',
              );
            case CommandFailed(:final Command command, :final String stderr):
              fail(
                '${name.name}: ${command.executable.name} '
                '${command.arguments.join(' ')} failed\n$stderr',
              );
            case Unstartable(:final Executable executable):
              fail('${name.name}: ${executable.name} is not on PATH');
            case StoreFailed(:final String path, :final String reason):
              fail('${name.name}: $path: $reason');
            case PinMissing(:final GitUrl url, :final Commit commit):
              fail('${name.name}: ${commit.hash} is not in ${url.url}');
          }
        }
    }
  });
}
```

`Muster.load` reads `muster.yaml`, brings each codebase to its pin in a checkout under `.dart_tool/muster/`, resolves it, and gives each its outcome. Every failure is a case of the sealed `FetchOutcome`, so the switch names each one and the test fails on all but `Fetched`, which carries the package to hand the tool under test.

A first load clones and resolves over the network, which can outlast `package:test`'s 30-second default, so `dart_test.yaml` beside the pubspec lifts it:

```yaml
timeout: none
```

## Run it

`dart test` runs it as any test. The first run clones equatable's repo into muster's cache and unpacks `path`, then fails, `<package>` standing for the package's own path:

```text
equatable has no lock: run `dart run muster lock` to write <package>/muster_locks/equatable-fffccec6aaf8a61d3e1eb51ce195d7ed9926d71200f7a110d0a6fe8d7b8fdac5.lock
```

Every codebase resolves on a lock, so its dependencies hold still as pub.dev publishes. equatable's commit holds no `pubspec.lock`, and no package from pub.dev holds one, so muster keeps a lock for each beside the manifest, and none is there yet.

## Write the locks

```sh
dart run muster lock
```

It resolves each package that lacks a lock afresh, equatable's example among them, and writes its lock into `muster_locks/`, a row each:

```text
name	outcome	detail
equatable	Wrote	<package>/muster_locks/equatable-fffccec6aaf8a61d3e1eb51ce195d7ed9926d71200f7a110d0a6fe8d7b8fdac5.lock
equatable	Wrote	<package>/muster_locks/equatable-fffccec6aaf8a61d3e1eb51ce195d7ed9926d71200f7a110d0a6fe8d7b8fdac5.example.lock
path	Wrote	<package>/muster_locks/path-a653a88a4eb21347ad189d3922101cd08251813d1ec986372662c4365fdcfc55.lock
```

Commit `muster_locks/`, so every run on every machine resolves on the same locks.

## Run it again

`dart test` passes now, and prints where each codebase stands and the SDK that resolved it:

```text
equatable at <package>/.dart_tool/muster/equatable, resolved by 3.13.7
path at <package>/.dart_tool/muster/path/path-1.9.1, resolved by 3.13.7
```

## Topics

- [Manifest](manifest.md) - each key a codebase takes, and the manifests a load reads.
- [Outcomes](outcomes.md) - what a load gives each codebase, and what a test does with each.
- [Refusals](refusals.md) - why a load refuses before it fetches anything.
- [Locks](locks.md) - the lock each codebase resolves on, and `muster lock`.
- [Scratches](scratches.md) - a worktree of a codebase's own, for a test that moves it off its pin.
- [Command line](command-line.md) - `muster fetch` and `muster lock`, their rows and their exit codes.
- [Environment](environment.md) - what muster runs, where its cache sits, the variables it reads and the platforms it passes on.

# muster

muster brings the real codebases your Dart and Flutter tools are tested against to the commits and versions you pin, resolved and ready to read. Each repo names what it needs in its own `muster.yaml`. Git history is cloned once into a cache every tool on the machine shares, and each tool gets a checkout of its own, so a tool's first `dart test` needs no setup and no fetch ever fails silently. Named for gathering scattered pieces into one place, ready for inspection, and for the test a tool must pass.

muster fetches and resolves, and nothing more: it runs no codebase's build or tests, manages no SDK, and keeps no copy of pub.dev's archives beside pub's own.

## Install

Until `v1.0.0` is on pub.dev, take muster as a git dev dependency, pinned by a release's tag:

```yaml
dev_dependencies:
  muster:
    git:
      url: https://github.com/lewis-dot-software/muster
      ref: <tag>
```

muster runs the `git`, `dart` and `flutter` on `PATH`, and reports the SDK version that resolved each codebase. It never installs or switches an SDK.

## A manifest

`muster.yaml` sits at your package's root and names each codebase by its key. This one, [example/muster.yaml](example/muster.yaml), pins equatable's repo at its `v3.0.0` commit, and `path` from pub.dev at `1.9.1`:

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

| Key | Kind | Sets |
|---|---|---|
| `git`, `commit` | Git | Its URL, and the full hash it is pinned at |
| `root` | Git | The package inside the repo that resolves and is handed out, `.` where it is left out |
| `hosted`, `version` | Hosted | A package from pub.dev at its version |
| `resolution` | Hosted | `alone` or `as-dependency`, `alone` where it is left out |
| `toolchain` | Both | `dart` or `flutter`, the one that resolves it, never left out |

A hosted package resolved `alone` takes its dev dependencies among its packages, as its own `pub get` would. One resolved `as-dependency` is the dependency of a package muster writes around it, its dev dependencies left out, for a package whose dev dependencies do not resolve.

A codebase's key is its name, `[a-z][a-z0-9_]*`, and names its checkout's directory. A key muster does not know, a value its key cannot take, or a name met twice across a load's manifests refuses the load before anything is fetched.

## A test

`Muster.load` reads the manifests, brings each codebase to its pin in a checkout under `.dart_tool/muster/`, resolves it, and returns one outcome per codebase. Every failure is a value of a sealed type, so a test switches on each and fails on all but `Fetched`, and no codebase is ever skipped in silence. This is [example/test/codebases_test.dart](example/test/codebases_test.dart):

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

The first run clones and resolves, and every run after hands the checkout out untouched while it stands at its pin. A tool may write beside a checkout's tracked files, but never moves it off its pin or edits a tracked file, since another test file may be reading it. A test that must, such as one replaying older commits, takes a scratch of its own from `Loaded.muster.scratch`.

## Locks

Every codebase resolves on a lock, so its dependencies hold still as pub.dev publishes. A git codebase whose commit holds a `pubspec.lock` resolves on that. Every other package, each hosted one among them, resolves on a kept lock: a lock muster keeps beside the manifest, in `muster_locks/` for `muster.yaml`. A load with no kept lock to take returns `Unlocked`, and one command writes every lock lacking:

```sh
dart run muster lock
```

Commit `muster_locks/`. A kept lock's file name carries a hash of the pin, `root`, `resolution` and toolchain, so any edit to those finds no lock and the next load returns `Unlocked` until `muster lock` runs again. It removes every lock its manifest no longer names.

## Commands

The `muster` command line runs over the manifests named, or `muster.yaml` in the working directory and every manifest `MUSTER_MANIFESTS` lists where none is:

| Command | Does |
|---|---|
| `muster fetch [manifest...]` | Loads, warming the cache and the checkouts, and prints a row per codebase |
| `muster lock [manifest...]` | Writes every kept lock lacking and removes those no codebase names, printing a row per lock |
| `muster --help` | Prints the usage, as `-h` and either command's own `--help` do |

Rows go to standard output, tab-separated under a header: the codebase's name, its outcome and that outcome's own detail. A refused run prints why and no rows. `muster fetch` prints the path for `Fetched`, followed by the dependency and its path quoted where the codebase's example was left unresolved, the lock for `Unlocked`, the command for `CommandFailed`, the executable for `Unstartable`, the path for `StoreFailed` and the commit for `PinMissing`. `muster lock` prints `Wrote` or `Removed` and the lock, or a failure as `muster fetch` prints it, a removed lock's name empty. A refusal, a usage error and what a failure's row leaves out, a command's exit code and output or the system's reason for a file act, go to standard error, a refusal in one line and each note in its row's order.

| Exit code | Means |
|---|---|
| `0` | Every codebase fetched, every lock written and removed, or the usage printed for `--help` |
| `1` | A codebase not fetched, or a lock not written or removed, each named in its row |
| `2` | A run refused before any process or file write |
| `64` | A command line muster does not take |

## Environment

| Variable | Sets |
|---|---|
| `MUSTER_CACHE` | The cache, where every git URL is cloned once with its whole history |
| `MUSTER_MANIFESTS` | Further manifests, a path list in the platform's separator, for codebases a public repo cannot name |

Where `MUSTER_CACHE` is unset, the cache is `$XDG_CACHE_HOME/muster` where that is an absolute path, else `~/.cache/muster`, and `%LOCALAPPDATA%\muster` on Windows in place of either. A variable set empty counts as unset. Deleting `.dart_tool/muster/` or the cache is always safe while no load runs, and costs one fetch.

## Platforms

The suite passes on macOS, and on Linux as a user other than root whose password is not locked. Windows is untested.

<!-- office doc index -->

## Docs

- [Architecture](docs/architecture.md) `knowledge` - A load reads a consumer's manifests, brings each codebase to its pin in a checkout of the consumer's own, resolves it with its toolchain, and returns one outcome per codebase.

<!-- /office doc index -->

## AI usage

Nothing here is "vibe-coded". Claude writes the code, far faster than I could by hand, but the design and the standard it's held to are mine. It runs inside tooling I've built on top of Claude Code, so every change is planned before it's written, then passes independent review, the full test suite and a strict quality gate before it reaches me. I review every line and send it back until it meets that standard, which is why every commit is mine. `CLAUDE.md` is gitignored because it holds details of my own setup, not to hide AI's part.

## Contributing

This repo is a public mirror of a private one, so nothing is ever merged here. Bug reports and feature requests are welcome as GitHub issues. A pull request is read as a proposal, and anything taken up is rebuilt and credited.

---
type: knowledge
aliases: Load, Loaded, FetchOutcome, Fetched, failures, Example, PackagePath, sealed outcomes
---

# Outcomes

`Muster.load()` returns a `Load`, and a loaded one gives every codebase a `FetchOutcome`. Each is a sealed type, so a test's switch names every case and the analyser fails the build when a case is missing. No failure throws, and none is ever a skip: a test fails on every case but `Fetched`.

## A load

| Case | Carries |
|---|---|
| `Loaded` | `outcomes`, each codebase's `FetchOutcome` keyed by its `CodebaseName`, in the manifests' order, and `muster`, the `Muster` that makes its scratches ([scratches](scratches.md)) |
| `Refused` | `reason`, the `LoadRefusal` that stopped the load before any process started or any file was written ([refusals](refusals.md)) |

A load brings its codebases to their pins one after another, and a failure in one goes on to the next, so every codebase has its outcome.

## A codebase

| Case | Carries |
|---|---|
| `Fetched` | `package`, the `PackagePath` to hand a tool, `example`, what was made of its example, and `sdk`, the `SdkVersion` that resolved it |
| `Unlocked` | `lock`, the `KeptLockPath` the codebase needs, which `muster lock` writes ([locks](locks.md)) |
| `CommandFailed` | `command`, the `Command` that failed, its `exitCode`, its `stdout` and its `stderr` |
| `Unstartable` | `executable`, the `Executable` that could not start: `git`, `dart` or `flutter` |
| `StoreFailed` | `path`, the path a file act failed on, and `reason`, what the system said |
| `PinMissing` | `url`, the `GitUrl` fetched, and `commit`, the pin's `Commit`, on none of its branches or tags |

Every case but `Fetched` is a `FetchFailure`. All but `Unlocked` are an `ActFailure` too, a failure of an act on the world outside muster, which a scratch's acts meet as well.

A `Command` is a record of its `executable` and its `arguments`. A `CodebaseName` reads back as its `name`, a `GitUrl` as its `url`, a `Commit` as its `hash`, and an `SdkVersion` is the version as its toolchain prints it: the Dart SDK's for `dart`, and the Flutter framework's for `flutter`.

## The package

A `PackagePath` is one package's directory, its `path`, beside the files its resolve reads and writes:

| Member | Is |
|---|---|
| `pubspec` | Its `pubspec.yaml`, a `PubspecPath` |
| `overrides` | Its `pubspec_overrides.yaml`, a `PubspecOverridesPath` |
| `lock` | The `pubspec.lock` its resolve wrote, a `LockPath` |
| `packageConfig` | The `package_config.json` its resolve wrote, a `PackageConfigPath` |

Each reads back as its `path`. A hosted package resolved `as-dependency` has its `lock` and `packageConfig` in the package muster writes around it, since that is where its resolve ran.

## The example

`Fetched.example` is an `Example`, a sealed type of its own:

| Case | Means |
|---|---|
| `NoExample` | The package holds no `example/` with a pubspec of its own |
| `ExampleResolved` | Its example resolved, its `package` a `PackagePath` |
| `ExampleUnresolved` | A hosted package's example was left unresolved, `outside` the path dependency that leaves the package |

`outside` is an `OutsidePath`, a record of the `dependency`, a `PackageName`, and its `path` as the example's pubspec writes it. An example that fails to resolve for any other reason fails its codebase.

## The checkout

A codebase's checkout sits under `.dart_tool/muster/<name>/` at the load's root. A git codebase's package is its `root` inside it, and a hosted one's is unpacked there as `<package>-<version>/`. The first load makes it and resolves it, and each load after hands it out untouched while it stands at its pin, resolved on the same lock by the same SDK. Any other checkout is made again.

A tool may write beside a checkout's tracked files, and what it writes there lasts across loads, but for a package's `pubspec.lock` and `.dart_tool/package_config.json`, which a load reads to find the checkout standing. It never moves a checkout off its pin or edits a tracked file ([scratches](scratches.md)).

A run of the codebase's own tests in its checkout is exposed, since `dart test` or `flutter test` may rewrite both files as it starts, and a load beside it or after it then finds the checkout no longer standing and makes it again, removing whatever the run made there. A tool that runs a git codebase's tests runs them in a scratch, and a hosted package's in a copy of the package outside its checkout, since a hosted codebase has no scratch.

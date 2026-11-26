---
type: knowledge
aliases: properties, invariants, property tests, property numbers
---

# Property index

Every property the code holds, each by its number beside its property test. A section holds each part of the code, named as its `area/` label names it, and a property sits under the part whose code holds it, the ones a reader most needs first. A number is the part's code and the property's place in its section, `LOA-1` and on, so it says at a glance which part holds the property, and none is worn twice.

A property's test wears its number and its words as its title, a property of three or more conditions read as one sentence there, its lead clause then each condition in order.

## CLI

### CLI-1: Fetch prints a row per codebase

`muster fetch` prints one row for each codebase in the load's order, its name, its outcome and that outcome's own detail, and each failure's note to standard error in its row's order, exiting 0 when every outcome is `Fetched`, 1 when any is not, and 2 with the refusal's line alone when the load is refused.

Test: [test/cli/cli_properties_test.dart](../test/cli/cli_properties_test.dart)

### CLI-2: Every row is three cells on one line

Every row `muster fetch` and `muster lock` print holds its header's three cells, each one line with no control character that reads back as the text it stands for, whatever a URL, a path or a command carries.

Test: [test/cli/cli_properties_test.dart](../test/cli/cli_properties_test.dart)

## Load

### LOA-1: A codebase's failure is its outcome

Every failure a codebase meets, git or hosted, comes back as its own outcome other than `Fetched`, every other codebase still getting its own, and none throws out of `Loader.load`.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### LOA-2: One outcome per codebase, in order

A load naming git and hosted codebases gives one outcome per codebase, fetched or failed, in the manifests' order, the root's `muster.yaml` first where one is read and the rest as listed or named, whatever its kind.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### LOA-3: A second load changes nothing

A load of git codebases right after another load hands out the same packages, examples and SDK versions, writes no file, and runs nothing but its SDK version reads and its git statuses.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### LOA-4: `Fetched` names its resolve's files

The lock and the package config a `Fetched` names, the example's among them, are the ones its codebase's resolve wrote, git or hosted, whatever its resolution.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### LOA-5: A deleted checkout or clone comes back

Each of these deleted by hand comes back at its path and its pin on the next load:

- A checkout.
- The whole of `.dart_tool/muster/`.
- Or a clone.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### LOA-6: A refused load leaves no trace

A load refused by its manifests or for want of a cache, a claim or a working directory refuses for that fault, starting no process and writing no file.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### LOA-7: A scratch moves apart from every checkout

A scratch worktree moves to any commit of its URL's, fetching one its clone lacks, without touching any consumer's checkout, and is gone with its clone's record of it once disposed of, a second disposal giving `Disposed` too.

Test: [test/load/scratch_properties_test.dart](../test/load/scratch_properties_test.dart)

### LOA-8: A failed scratch is an outcome

A scratch that cannot be made comes back as `NotNamed`, starting no process, or as `ScratchFailed` for the act that failed, leaving no directory behind, never as a throw.

Test: [test/load/scratch_properties_test.dart](../test/load/scratch_properties_test.dart)

### LOA-9: Every type the library names is exported

Every type a public member of the library names is exported by `lib/muster.dart`.

Test: [test/surface_test.dart](../test/surface_test.dart)

### LOA-10: A refusal reads as one line

Every `LoadRefusal` reads as one line holding no control character but a tab, whatever its paths and reasons hold, and so does the refusal of a load of any manifest at any path.

Test: [test/load/refusal_properties_test.dart](../test/load/refusal_properties_test.dart)

### LOA-11: Each SDK version is read once

A load reads each toolchain's SDK version once where any codebase, git or hosted, names it and never otherwise, each codebase it resolves carrying that version and each of a failed read failing with it.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### LOA-12: A hosted scratch is `NotGit`

A scratch asked of a hosted codebase gives `NotGit` and starts no process.

Test: [test/load/scratch_properties_test.dart](../test/load/scratch_properties_test.dart)

### LOA-13: `NoCache` names its system's variables

The `NoCache` text names exactly the variables its system weighs, each of which alone names a cache there, and no other variable does.

Test: [test/load/refusal_properties_test.dart](../test/load/refusal_properties_test.dart)

### LOA-14: A scratch is made whatever the load gave

A scratch is made at its pin, holding the pin's files, whatever its codebase's load gave and whether its clone was deleted since.

Test: [test/load/scratch_properties_test.dart](../test/load/scratch_properties_test.dart)

### LOA-15: A move off every ref is `PinMissing`

A move to a commit on none of its URL's branches or tags gives `MoveFailed` for `PinMissing`, naming that commit, the scratch left at the commit it was at and no checkout touched.

Test: [test/load/scratch_properties_test.dart](../test/load/scratch_properties_test.dart)

### LOA-16: A scratch waits on a load's clone claim

A scratch's make, move and disposal each wait on a load's claim on its clone, in an isolate or a process of its own, running no command until the load lets it go.

Test: [test/load/scratch_properties_test.dart](../test/load/scratch_properties_test.dart)

### LOA-17: A failed scratch that cannot be removed stays

A `ScratchFailed` whose directory cannot be removed leaves that directory in the temporary directory, carrying the failure of the act that failed and throwing nothing.

Test: [test/load/scratch_properties_test.dart](../test/load/scratch_properties_test.dart)

## Manifest

### MAN-1: A lock writes what is lacking, then nothing

`muster lock` writes a kept lock for each package that needs one and has none, leaves every existing lock untouched, and removes every lock and partial its manifest no longer names, so a second run changes nothing.

Test: [test/load/lock_properties_test.dart](../test/load/lock_properties_test.dart)

### MAN-2: A git package takes its commit's lock first

The lock chosen for each package a git codebase resolves, its `root` and an `example/` with a pubspec of its own, is the `pubspec.lock` its commit holds there, else its kept lock, and with neither the first such package, the root's before the example's, is the one lacking.

Test: [test/model/choose_properties_test.dart](../test/model/choose_properties_test.dart)

### MAN-3: Each package resolves on its own kept lock

A package and its example each resolve on their own kept lock, never the lock pub serves, and a lock that is missing gives `Unlocked`, naming the first missing, the root's before the example's.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### MAN-4: A git lock key moves on resolve values alone

Two git codebases share a kept lock's key exactly when they agree on URL as written, commit, `root` and toolchain, and neither a rename, a `root` spelt another way, the keys' order nor the codebases beside it moves the key.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-5: A hosted lock key moves on resolve values alone

Two hosted codebases' kept locks share a key exactly when their package, version, resolution and toolchain are the same, and never share one with a git codebase.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-6: A hosted lock lets the load fetch

`muster lock` writes the kept locks a hosted package and its example lack, leaving those that stand, and a load after it gives `Fetched`.

Test: [test/load/lock_properties_test.dart](../test/load/lock_properties_test.dart)

### MAN-7: Codebases come back in order, each name once

A parse gives the codebases back in the manifests' order, each under its own name, and the first name met twice across them refuses, naming it and the manifests it is met in.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-8: A bad git value refuses at its path

A value its key cannot take refuses the load, naming that key's path:

- A git URL that is empty or opens on `-`.
- A commit that is not a full hash.
- A toolchain that is not `dart` or `flutter`.
- A `root` that leaves its repo or holds a `\`.
- Or a codebase name that is not `[a-z][a-z0-9_]*`.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-9: A bad hosted value refuses at its path

A hosted codebase's `hosted` is a pub package name and its `version` a version pub reads, and any other text refuses the load, naming its key's path.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-10: A missing required key refuses at its path

A git codebase missing `git`, `commit` or `toolchain`, or a hosted one missing `hosted`, `version` or `toolchain`, refuses the load, naming that key's path.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-11: A codebase of both kinds or neither refuses

A codebase holding no key of either kind refuses the load, naming the codebase's path, and one holding keys of both refuses at the first key of the kind its first kind's key does not name.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-12: An unknown key refuses at its path

A key muster does not know, at the top or in a codebase, refuses the load, naming that key's path from the top.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-13: A resolution left out is `alone`

A `resolution` left out reads as `alone`, and any value but `alone` or `as-dependency` refuses, naming its key's path.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-14: A broken named manifest refuses

A named manifest refuses the load, naming the file and why, and for its text where the read stopped, where it is one of these:

- Missing.
- Unreadable.
- Not UTF-8.
- Or not YAML.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### MAN-15: No manifest refuses, naming the root

A load with no manifest at all refuses, naming its root: no `muster.yaml` at the root and nothing in `MUSTER_MANIFESTS`.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### MAN-16: A name needs a stem before `.yaml`

A manifest whose file name does not end `.yaml` after a stem of its own refuses the load.

Test: [test/load/load_properties_test.dart](../test/load/load_properties_test.dart)

### MAN-17: A line break in a URL or root refuses

A git URL or a `root` holding a character that breaks a line refuses the load, naming its key's path.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-18: Unnamed locks and partials are chosen for removal

Of the files a locks directory lists, every kept lock and partial no codebase names is chosen for removal, in their file names' order, and nothing else is.

Test: [test/model/lock_choices_test.dart](../test/model/lock_choices_test.dart)

### MAN-19: Key paths are the same when their keys are

Two key paths are the same exactly when their keys are, whatever a key holds, an empty key and ones holding a dot, a quote or a character that breaks a line among them.

Test: [test/model/key_path_properties_test.dart](../test/model/key_path_properties_test.dart)

### MAN-20: A warned directive changes nothing

A directive the YAML reader warns of, opening a manifest, leaves its parse as it stands without one, and prints nothing.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-21: A bare manifest parses as its quoted twin

A manifest written with its keys and values bare parses as its quoted twin, a hash of digits alone and a name or a root YAML reads as a null, a bool or a number among them.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-22: A refusal writes back what the manifest wrote

A refused value's `written` is what the manifest wrote in its place, a plain value as its text with its quotes, a list, a mapping or nothing.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-23: The first fault the parse weighs refuses

Of several faults in a manifest, the one refused is the first the parse weighs: an unknown key at the top, then each codebase in the text's order, by its name, then the first key in the text's order it does not know, then its want of a kind, then its kind's keys in the order `git`, `commit`, `root` and `toolchain`, or `hosted`, `version`, `resolution` and `toolchain`.

Test: [test/model/manifest_properties_test.dart](../test/model/manifest_properties_test.dart)

### MAN-24: A name met twice names both manifests

A name met in two of a load's manifests refuses the load, naming it, the manifest it is first met in and the one it is met in again, whether each manifest is named, at the root or listed, and where one manifest is given twice.

Test: [test/load/named_twice_properties_test.dart](../test/load/named_twice_properties_test.dart)

### MAN-25: A git checkout holds its chosen lock

A git checkout holds the lock chosen for each package it resolves as its `pubspec.lock`, its commit's before its kept lock, its `root` and its `example/` alike.

Test: [test/store/placed_lock_properties_test.dart](../test/store/placed_lock_properties_test.dart)

## Store

### STO-1: Two loads never act on one clone or checkout together

Two loads at once, as isolates of one process or as separate processes, never act on one clone or checkout together, git or hosted: the second waits, uses the first's clone with no clone or fetch of its own, and hands out the first's checkout untouched where they share one.

Test: [test/load/concurrency_properties_test.dart](../test/load/concurrency_properties_test.dart)

### STO-2: A git checkout stands only as stamped

A git checkout stands exactly when each of these holds, and does not stand where any one is off:

- Its stamp matches the codebase's values, the lock each package holds, a kept lock's source beside its manifest and the SDK version on PATH.
- The package it hands out is there.
- `HEAD` is the pin.
- No tracked file has changed.
- And each `package_config.json` is the one it was stamped with.

Test: [test/model/stands_properties_test.dart](../test/model/stands_properties_test.dart)

### STO-3: A hosted checkout stands only as stamped

A hosted checkout stands exactly when each of these holds, whatever a worktree or a package the stamp does not name shows and whether its example was left unresolved, and does not stand where any one is off:

- Its stamp matches the codebase's values and the SDK version on PATH.
- The package it hands out is there.
- Each package holds the lock and the `package_config.json` it was stamped with.
- And its kept lock beside its manifest is the one it resolved on.

Test: [test/model/stands_properties_test.dart](../test/model/stands_properties_test.dart)

### STO-4: A checkout made again holds the pin's files alone

A checkout made again holds exactly the pin's tracked files, whatever stood in its place: every edit is reverted and every file the pin lacks is removed.

Test: [test/store/checkout_properties_test.dart](../test/store/checkout_properties_test.dart)

### STO-5: A changed hosted checkout is unpacked afresh

A hosted checkout is unpacked afresh, and then stands, where any of these holds:

- Its stamp is gone or differs.
- Its lock, kept lock or `package_config.json` is not the one stamped.
- Or its package has lost its pubspec.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-6: A fresh hosted checkout holds what pub serves

A hosted checkout made afresh holds every file pub serves for the package at its version, unchanged but for the `pubspec.lock` of a package that resolves in place, which its resolve replaces with its kept lock, and nothing beside them but what the resolve, the package around it and each package's `pubspec_overrides.yaml` write.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-7: A dead or failed load's claim never blocks the next

A claim held by a load that crashed, which never released it, or that failed, which released it as the failure unwound, never blocks a later load, which hands out the checkout made whole and leaves no temporary clone.

Test: [test/load/concurrency_properties_test.dart](../test/load/concurrency_properties_test.dart)

### STO-8: A standing checkout keeps what a tool wrote

A standing checkout keeps everything a tool wrote beside its tracked files, ignored or untracked, and is handed out with nothing run but its survey.

Test: [test/store/checkout_properties_test.dart](../test/store/checkout_properties_test.dart)

### STO-9: A standing hosted checkout is handed out untouched

A second checkout of a hosted codebase hands the first out untouched, starting no process but its SDK's version read.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-10: A pin off the default branch is still reached

A pin reachable only from a branch or tag that isn't the default branch is still reached.

Test: [test/store/cache_properties_test.dart](../test/store/cache_properties_test.dart)

### STO-11: Resolution decides the dev dependencies

A hosted package resolved `alone` resolves with its dev dependencies, and one resolved `as-dependency` without them.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-12: An example is left unresolved only for a leaving path

A hosted package's example is left unresolved exactly when its pubspec path-depends outside the package on a package muster does not override to the package's own path, and `Fetched` names the first such dependency and its path as the pubspec writes it.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-13: Any other example failure fails its codebase

A hosted example that fails to resolve for any other reason fails its codebase, by `muster lock` and by a checkout alike, never `Fetched`.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-14: A leaving path is read as pub reads it

A hosted example is left unresolved exactly where a path dependency of it, read as pub reads it, leaves the package, and a pubspec or served overrides that pub would refuse fails its codebase.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-15: A clone holding the pin is never fetched

A clone that already holds the pin's commit is never fetched.

Test: [test/store/cache_properties_test.dart](../test/store/cache_properties_test.dart)

### STO-16: A dependency back on an `as-dependency` package takes the package itself

A package resolved `as-dependency` resolves where a dependency of it, direct or through others, depends back on it from the host it is served from, whatever its constraint, and that dependency takes the package itself.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-17: `alone` drops the overrides a package publishes

A hosted package resolved `alone` resolves with none of the `dependency_overrides` its pubspec publishes.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-18: A stamp reads back as written

A stamp written and then read gives back the values it was written from.

Test: [test/model/stamp_properties_test.dart](../test/model/stamp_properties_test.dart)

### STO-19: The cache follows its chain on either system

The cache is `MUSTER_CACHE` on either system where it is set, else on Windows `muster` under `LOCALAPPDATA`, and elsewhere `muster` under `XDG_CACHE_HOME` where that is an absolute path, else `.cache/muster` under `HOME`, and none where none of those stands, a variable set empty counting as unset and nothing else set moving it.

Test: [test/model/cache_directory_test.dart](../test/model/cache_directory_test.dart)

### STO-20: A hosted checkout starts no git

A hosted codebase's lock and checkout take no clone's claim, start no git and make no cache.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-21: A clone sweeps every unheld temporary clone

A clone removes every temporary clone in the cache whose claim no other hold has, and leaves every one whose claim is held, never waiting on it, and every entry that is no temporary clone.

Test: [test/store/cache_properties_test.dart](../test/store/cache_properties_test.dart)

### STO-22: Codebases share a clone exactly when URLs match

Two codebases share a clone exactly when their URLs are the same string.

Test: [test/model/clone_path_test.dart](../test/model/clone_path_test.dart)

### STO-23: A clone is cloned, fetched once or used as it stands

Each of these holds of a clone:

- One that is missing is cloned.
- One that lacks the pin's commit is fetched once.
- One that holds it is left untouched.
- And one that still lacks it after its fetch is `PinMissing`.

Test: [test/model/step_properties_test.dart](../test/model/step_properties_test.dart)

### STO-24: Only a worktree of its clone is moved

A checkout that is a worktree of its URL's clone is moved to its pin, and any other is removed and added afresh.

Test: [test/model/step_properties_test.dart](../test/model/step_properties_test.dart)

### STO-25: A temporary clone reads back as its clone

A temporary clone's name is read back as the clone it is made for, whatever letters and digits its token holds.

Test: [test/model/clone_path_test.dart](../test/model/clone_path_test.dart)

### STO-26: Only `macos` and `linux` name a kernel

`macos` names Darwin's kernel, `linux` names Linux's, and no other system names one.

Test: [test/store/locker_test.dart](../test/store/locker_test.dart)

### STO-27: Loads over several codebases never wait on each other

Two loads at once over several codebases, git and hosted, sharing a root or a clone alone, each in an order of its own, never wait on each other, and each gives every codebase `Fetched`.

Test: [test/load/concurrency_properties_test.dart](../test/load/concurrency_properties_test.dart)

### STO-28: A standing hosted checkout keeps what a tool wrote

A standing hosted checkout keeps every file a tool wrote in it beside the files pub serves and the resolve's, and is handed out with nothing run but its SDK's version read.

Test: [test/store/hosted_properties_test.dart](../test/store/hosted_properties_test.dart)

### STO-29: A failed make leaves no stamp

A make cut short or failed, git or hosted, leaves no stamp once it has touched the checkout, even one an earlier make wrote, and the stamp as it stood before then, so the next load makes the checkout again.

Test: [test/load/concurrency_properties_test.dart](../test/load/concurrency_properties_test.dart)

### STO-30: Any stamp bytes never fail a checkout

Any bytes in a stamp file read as a stamp or as none, and never fail a checkout, which then stands.

Test: [test/store/checkout_properties_test.dart](../test/store/checkout_properties_test.dart)

---
type: knowledge
aliases: Refused, LoadRefusal, ManifestRefusal, BadValue, Wanted, Written, KeyPath, refused load
---

# Refusals

A load refuses before it starts any process or writes any file, where it cannot start: its manifests do not hold, or the machine gives it no working directory, no cache or no claim. `Refused.reason` is the `LoadRefusal`, a sealed type with a case for each.

Each refusal reads as the line `muster fetch` prints for it, naming its case and what it carries, so a test's `fail('The load refused: $reason')` says why. A `ManifestRefusal` reads as that line after its manifest's path.

## A load's refusal

| Case | Carries | Refuses |
|---|---|---|
| `NoManifest` | `root` | A load with no manifest: none named, no `muster.yaml` at its root, and none in `MUSTER_MANIFESTS` |
| `NotManifestName` | `path` | A manifest whose file name does not end `.yaml` |
| `ManifestMissing` | `manifest` | A manifest named that is not there |
| `ManifestUnreadable` | `manifest`, `reason` | A manifest whose file could not be read, for the reason the system gave |
| `ManifestInvalid` | `manifest`, `refusal` | A manifest whose text refused to parse, for its `ManifestRefusal` |
| `CodebaseNamedTwice` | `name`, `first`, `second` | A codebase's name met in two of the load's manifests |
| `NoWorkingDirectory` | `reason` | A working directory the system cannot give, as where it has been deleted |
| `NoCache` | `os` | A machine with none of the variables set that the cache is taken from ([environment](environment.md)) |
| `NoClaim` | `system` | A POSIX system whose C library muster does not know, so it has no lock to claim a clone or a checkout with |

A `ManifestPath` reads back as its `path`, and so does a `ConsumerRoot`, the directory a load seeks its `muster.yaml` at and stands its checkouts under. Each one's `os`, an `Os`, is `posix` or `windows`, the family of system whose paths it is written in.

## A manifest's refusal

`ManifestInvalid.refusal` is a `ManifestRefusal`, which names the key it refused at:

| Case | Carries | Refuses |
|---|---|---|
| `NotYaml` | `reason` | Text that is not one YAML document, or bytes that are not UTF-8, the reader's reason in one line with where it stopped |
| `UnknownKey` | `path` | A key muster does not know, a key of the other kind's among them |
| `MissingKey` | `path` | A key left out that its mapping must hold: the top's `codebases`, or one a codebase must hold |
| `MissingKind` | `path` | A codebase holding neither kind's keys, so neither git nor hosted |
| `BadValue` | `path`, `wanted`, `written` | A value its key cannot take, or a codebase's key that is no codebase name |

A `KeyPath` is where a key sits, read back as `dotted`: each key from the top joined by `.`, as `codebases.app.root` is. A key that is empty, holds a `.`, opens on `"`, or holds a control character but a tab, or Unicode's line or paragraph separator, is quoted, as `codebases."a.b"` is. `KeyPath.top` is the manifest's top, above every key.

## A bad value

`BadValue.wanted` is a `Wanted`, naming the value its key takes, each as the [manifest](manifest.md) gives it:

| Value | Must be |
|---|---|
| `mapping` | A mapping of keys to values |
| `codebaseName` | A codebase's key |
| `packageName` | A `hosted` package's name |
| `gitUrl` | A `git` URL |
| `fullHash` | A `commit`'s full hash |
| `toolchain` | A `toolchain` |
| `rootInsideRepo` | A `root` inside its repo |
| `version` | A `version` pub reads, as `1.2.3` or `2.0.0-dev.1` is |
| `resolution` | A `resolution` |

`BadValue.written` is a `Written`, what the manifest wrote in its place:

| Case | Is |
|---|---|
| `WrittenText` | A plain value, its `text` as the manifest writes it, its quotes among it |
| `WrittenList` | A list |
| `WrittenMapping` | A mapping |
| `WrittenNothing` | Nothing at all, as an empty manifest or a key with no value writes |

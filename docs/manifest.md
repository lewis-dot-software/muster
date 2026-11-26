---
type: knowledge
aliases: muster.yaml, keys, codebases, git codebase, hosted codebase, toolchain, resolution, MUSTER_MANIFESTS
---

# Manifest

A manifest is a YAML file naming the codebases a package's tests load, each under its key in a `codebases` mapping. `muster.yaml` at the package's root is the one a load reads first, and further manifests name codebases a public repo cannot, so each sits outside that repo, in one of its own.

## Codebases

Each codebase is one of two kinds. A git codebase is a repo at a commit, and a hosted codebase is a package on pub.dev at a version:

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

Every value is read as the text it is written as, quoted or not, so a commit of digits alone or a codebase named `null` reads as written, and a value left empty is none.

A git URL is any URL git clones, an SSH one among them, that does not open on `-` and holds no control character but a tab, nor Unicode's line or paragraph separator. It is cloned as written, so two spellings of one repo are two clones. A commit is its full hash, 40 or 64 lowercase hexadecimal digits, never a branch or a tag, since those move. A `root` is a relative path that stays inside its repo, holds no `\`, and holds none of the characters a URL may not.

A hosted package resolved `alone` takes its dev dependencies among its packages, as its own `pub get` would. One resolved `as-dependency` is the dependency of a package muster writes around it, its dev dependencies left out, for a package whose dev dependencies do not resolve.

A package's `example/`, where it holds one with a pubspec of its own, resolves beside it. A hosted package's example with a path dependency that leaves the package, which pub does not serve, is left unresolved, and its codebase still loads ([outcomes](outcomes.md)). Any other example that fails to resolve fails its codebase.

## Keys

A codebase's key is its name, `[a-z][a-z0-9_]*`, and names its checkout's directory and its kept locks. A key muster does not know, a value its key cannot take, a codebase holding neither kind's keys or both, or a name met twice across a load's manifests refuses the load before anything is fetched, naming the key's path ([refusals](refusals.md)).

## The manifests a load reads

`Muster.load()` reads `muster.yaml` at its root and every manifest `MUSTER_MANIFESTS` lists, a path list in the platform's separator, `:` and `;` on Windows. A manifest's file name ends `.yaml`, and one named that is missing refuses the load ([refusals](refusals.md)).

`Muster.load(manifests: [...])` reads the manifests given in place of both. Its `root` is the directory the checkouts stand under, `.dart_tool/muster/` inside it, and is the working directory where it is left out. A relative path, a manifest's or the root's, is read against the working directory. Wherever its manifests sit, a load's checkouts stand under its root.

Each manifest's kept locks sit beside it ([locks](locks.md)).

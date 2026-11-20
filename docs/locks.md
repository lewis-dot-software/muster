---
type: knowledge
aliases: pubspec.lock, kept lock, muster_locks, muster lock, Unlocked, lock key
---

# Locks

Every codebase resolves on a lock, so its dependencies hold still as pub.dev publishes and every machine resolves it alike. A load never resolves a package without one: where it finds none, the codebase is `Unlocked`, and `dart run muster lock` writes what is lacking.

## Which lock a package takes

A package is a codebase's own, or the `example/` inside it where that holds a pubspec of its own.

| Package | Resolves on |
|---|---|
| A git codebase's, where its commit holds a `pubspec.lock` beside its pubspec | That lock |
| A git codebase's, where its commit holds none there | A kept lock |
| A hosted codebase's, its example's among them | A kept lock |

A hosted example left unresolved takes no lock ([outcomes](outcomes.md)).

## Kept locks

A kept lock is a lock muster keeps beside a manifest, in `<stem>_locks/`, so `muster.yaml`'s are in `muster_locks/` and a further manifest's in a directory of its own. Its file is `<name>-<key>.lock`, and an example's adds `.example` before `.lock`. Commit the directory in its manifest's repo, since a machine without it resolves nothing that needs one.

The key is a hash of every manifest value the resolve turns on: the source, the git URL as written or the hosted package's name, then the pin, `root` for a git codebase, `resolution` for a hosted one, and the toolchain. So an edit to any of those, a URL spelled another way among them, finds no lock and the next load returns `Unlocked` until `muster lock` runs again, never a resolution on a lock made for other values.

A load copies a kept lock into its package as `pubspec.lock` before it resolves, so a git checkout carries one as a file its pin lacks.

## Writing them

```sh
dart run muster lock
```

`muster lock` resolves afresh each package that needs a kept lock and has none, in its codebase's checkout made again at its pin, and writes the lock that resolve gives. It leaves every lock that stands, so a lock is written afresh by deleting its file and running it again. It then removes every lock in the directory that no codebase of its manifest names, so a codebase dropped or edited leaves nothing behind.

Each lock is written to `<file>.partial` beside it and then moved into place, so a write cut short never leaves part of a lock. A file there whose name ends neither `.lock` nor `.lock.partial` is left alone.

It reads the same manifests as a load, and its rows and exit codes are the [command line](command-line.md)'s.

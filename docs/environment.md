---
type: knowledge
aliases: MUSTER_CACHE, MUSTER_MANIFESTS, cache, SDK, PATH, credentials, platforms, Windows, Linux, macOS
---

# Environment

muster runs the `git`, `dart` and `flutter` on `PATH`, keeps one cache of clones every package on the machine shares, and reads two variables of its own. It never installs or switches an SDK.

## Toolchains

Each codebase resolves with the toolchain its manifest names, the `dart` or `flutter` on `PATH`, and `Fetched.sdk` names the SDK version that resolved it ([outcomes](outcomes.md)). A hosted package is unpacked by `dart` whichever toolchain resolves it. On Windows `flutter` starts as `flutter.bat`, the script the Flutter SDK holds on `PATH`, since Windows finds a name with no extension there only as a `.exe`. Windows runs that script in `cmd`, so a consumer's root whose path holds a character `cmd` reads, such as `&` or `%`, may not reach `flutter` whole. A checkout stamped by another SDK than the one on `PATH` is made again on the next load.

## Variables

| Variable | Sets |
|---|---|
| `MUSTER_CACHE` | The cache, where every git URL is cloned once with its whole history |
| `MUSTER_MANIFESTS` | Further manifests, for codebases a public repo cannot name ([manifest](manifest.md)) |

Where `MUSTER_CACHE` is unset, the cache is `$XDG_CACHE_HOME/muster` where that is an absolute path, else `~/.cache/muster`, and `%LOCALAPPDATA%\muster` on Windows in place of either. A variable set empty counts as unset, and a load with none of them refuses as `NoCache` ([refusals](refusals.md)).

Every process muster starts takes the environment muster was started with. Git starts without the variables that point it at a repo, such as the `GIT_DIR` a hook exports, so it acts on muster's repos alone.

## Credentials

No process muster starts asks anything. Git's terminal prompt is off unless the environment sets `GIT_TERMINAL_PROMPT`, and no askpass program runs, git's or ssh's, so where git, the ssh it runs or pub's git would ask for credentials, a passphrase or a host's trust, it fails instead, as a `CommandFailed`. A credential helper, an ssh agent, `core.sshCommand` and known hosts still serve. An ssh older than OpenSSH 8.4 still asks on the terminal where one stands.

## The cache and the checkouts

Deleting `.dart_tool/muster/` or the cache is always safe while no load runs, and costs one fetch. Loads in isolates of one `dart test` and in separate processes, `flutter test`'s among them, wait on one another for a clone or a checkout, so test files run in parallel share both safely.

## Platforms

The suite passes on macOS and on Linux. Windows is untested.

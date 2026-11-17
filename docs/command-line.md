---
type: knowledge
aliases: CLI, muster fetch, muster lock, rows, exit codes, dart run muster
---

# Command line

The `muster` command line warms the cache and the checkouts ahead of a test, and writes the kept locks. A package that depends on muster runs it as `dart run muster <command>`.

## Commands

Each command runs over the manifests named, or where none is over those a load reads, its root the working directory ([manifest](manifest.md)):

| Command | Does |
|---|---|
| `muster fetch [manifest...]` | Loads, warming the cache and the checkouts, and prints a row per codebase |
| `muster lock [manifest...]` | Writes every kept lock lacking and removes those no codebase names, printing a row per lock ([locks](locks.md)) |
| `muster --help` | Prints the usage, as `-h` and either command's own `--help` do |

## Rows

Rows go to standard output, tab-separated under a header: the codebase's name, its outcome and that outcome's own detail. A refused run prints why and no rows.

`muster fetch` prints, for each outcome:

| Outcome | Detail |
|---|---|
| `Fetched` | The package's path, then the dependency and its path quoted where the codebase's example was left unresolved |
| `Unlocked` | The kept lock it needs |
| `CommandFailed` | The command |
| `Unstartable` | The executable |
| `StoreFailed` | The path |
| `PinMissing` | The commit |

`muster lock` prints `Wrote` or `Removed` and the lock, or a failure as `muster fetch` prints it, a removed lock's name empty.

A detail holding a tab, a line break or another control character, or opening on `"`, is quoted as a JSON string, so every row holds its three cells on one line. A refusal, a usage error and what a failure's row leaves out, a command's exit code and output or the system's reason for a file act, go to standard error, a refusal in one line and each note in its row's order.

## Exit codes

| Exit code | Means |
|---|---|
| `0` | Every codebase fetched, every lock written and removed, or the usage printed for `--help` |
| `1` | A codebase not fetched, or a lock not written or removed, each named in its row |
| `2` | A run refused before any process or file write ([refusals](refusals.md)) |
| `64` | A command line muster does not take |

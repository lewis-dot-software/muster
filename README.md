# muster

muster brings the real codebases your Dart and Flutter tools are tested against to the commits and versions you pin, resolved and ready to read. Each repo names what it needs in its own `muster.yaml`. Git history is cloned once into a cache every tool on the machine shares, and each tool gets a checkout of its own, so a tool's first `dart test` needs no setup and no fetch ever fails silently. Named for gathering scattered pieces into one place, ready for inspection, and for the test a tool must pass.

muster fetches and resolves, and nothing more: it runs no codebase's build or tests, manages no SDK, and keeps no copy of pub.dev's archives beside pub's own.

## Install

Until `v1.0.0` reaches pub.dev, pin a tag of this repo as a dev dependency:

```yaml
dev_dependencies:
  muster:
    git:
      url: https://github.com/lewis-dot-software/muster
      ref: v0.2.1
  test: ^1.33.0
```

## A manifest

`muster.yaml` at a package's root names the codebases its tests load. This one, [example/muster.yaml](example/muster.yaml), pins equatable's repo at its `v3.0.0` commit, and `path` from pub.dev at `1.9.1`:

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

A test's `await Muster.load()` brings each to its pin in a checkout under `.dart_tool/muster/`, resolved on its lock, and gives each an outcome, every failure among them a value the test fails on, so no codebase is ever skipped in silence.

The [quickstart](docs/quickstart.md) writes that test, writes the locks and loads both codebases, and links a doc per topic.

<!-- office doc index -->

## Docs

- [Architecture](docs/architecture.md) - A load reads a consumer's manifests, brings each codebase to its pin in a checkout of the consumer's own, resolves it with its toolchain, and returns one outcome per codebase.
- [Command line](docs/command-line.md) - The `muster` command line warms the cache and the checkouts ahead of a test, and writes the kept locks.
- [Environment](docs/environment.md) - muster runs the `git`, `dart` and `flutter` on `PATH`, keeps one cache of clones every package on the machine shares, and reads two variables of its own.
- [Locks](docs/locks.md) - Every codebase resolves on a lock, so its dependencies hold still as pub.dev publishes and every machine resolves it alike.
- [Manifest](docs/manifest.md) - A manifest is a YAML file naming the codebases a package's tests load, each under its key in a `codebases` mapping.
- [Outcomes](docs/outcomes.md) - `Muster.load()` returns a `Load`, and a loaded one gives every codebase a `FetchOutcome`.
- [Quickstart](docs/quickstart.md) - This page installs muster in a package, names two codebases for its tests, and loads them in a test, writing their locks on the way, then links a doc for each topic it touches.
- [Refusals](docs/refusals.md) - A load refuses before it starts any process or writes any file, where it cannot start: its manifests do not hold, or the machine gives it no working directory, no cache or no claim.
- [Scratches](docs/scratches.md) - A scratch is a worktree of a git codebase's clone in a temporary directory, a test's own to move to any commit.

<!-- /office doc index -->

## AI usage

Nothing here is "vibe-coded". Claude writes the code, far faster than I could by hand, but the design and the standard it's held to are mine. It runs inside tooling I've built on top of Claude Code, so every change is planned before it's written, then passes independent review, the full test suite and a strict quality gate before it reaches me. I review every line and send it back until it meets that standard, which is why every commit is mine. `CLAUDE.md` is gitignored because it holds details of my own setup, not to hide AI's part.

## Contributing

This repo is a public mirror of a private one, so nothing is ever merged here. Bug reports and feature requests are welcome as GitHub issues. A pull request is read as a proposal, and anything taken up is rebuilt and credited.

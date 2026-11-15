# muster

muster brings the real codebases your Dart and Flutter tools are tested against to the commits and versions you pin, resolved and ready to read. Each repo names what it needs in its own `muster.yaml`. Git history is cloned once into a cache every tool on the machine shares, and each tool gets a checkout of its own, so a tool's first `dart test` needs no setup and no fetch ever fails silently. Named for gathering scattered pieces into one place, ready for inspection, and for the test a tool must pass.

<!-- office doc index -->

## Docs

- [Architecture](docs/architecture.md) `knowledge` - A load reads a consumer's manifests, brings each codebase to its pin in a checkout of the consumer's own, resolves it with its toolchain, and returns one outcome per codebase.

<!-- /office doc index -->

## AI usage

Nothing here is "vibe-coded". Claude writes the code, far faster than I could by hand, but the design and the standard it's held to are mine. It runs inside tooling I've built on top of Claude Code, so every change is planned before it's written, then passes independent review, the full test suite and a strict quality gate before it reaches me. I review every line and send it back until it meets that standard, which is why every commit is mine. `CLAUDE.md` is gitignored because it holds details of my own setup, not to hide AI's part.

## Contributing

This repo is a public mirror of a private one, so nothing is ever merged here. Bug reports and feature requests are welcome as GitHub issues. A pull request is read as a proposal, and anything taken up is rebuilt and credited.

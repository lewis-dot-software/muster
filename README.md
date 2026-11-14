# muster

muster brings the real codebases your Dart and Flutter tools are tested against to the commits and versions you pin, resolved and ready to read. Each repo names what it needs in its own `muster.yaml`. Git history is cloned once into a cache every tool on the machine shares, and each tool gets a checkout of its own, so a tool's first `dart test` needs no setup and no fetch ever fails silently. Named for gathering scattered pieces into one place, ready for inspection, and for the test a tool must pass.

**Status:** v0.2.0 Hosted is the current milestone.

<!-- office doc index -->

## Docs

- [Architecture](docs/architecture.md) `knowledge` - A load reads a consumer's manifests, brings each codebase to its pin in a checkout of the consumer's own, resolves it with its toolchain, and returns one outcome per codebase.

<!-- /office doc index -->

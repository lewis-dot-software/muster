# muster

muster brings the real codebases your Dart and Flutter tools are tested against to the commits and versions you pin, resolved and ready to read. Each repo names what it needs in its own `muster.yaml`. Git history is cloned once into a cache every tool on the machine shares, and each tool gets a checkout of its own, so a tool's first `dart test` needs no setup and no fetch ever fails silently. Named for gathering scattered pieces into one place, ready for inspection, and for the test a tool must pass.

**Status:** v0.1.0 Git is the current milestone.

<!-- office doc index -->

<!-- /office doc index -->

---
type: knowledge
aliases: Scratch, Muster.scratch, move, dispose, older commits, replay, worktree
---

# Scratches

A scratch is a worktree of a git codebase's clone in a temporary directory, a test's own to move to any commit. A checkout is shared by every test file that loads its codebase, so none may move it off its pin, and a test that must, such as one replaying older commits or one running the codebase's own tests, takes a scratch instead.

## Making one

`Loaded.muster` makes a scratch of any git codebase the load's manifests name, by its `CodebaseName`. `muster.scratch(name)` returns a `Scratching`:

| Case | Means |
|---|---|
| `Scratched` | The scratch, `scratch`, a `Scratch` at the codebase's pin |
| `NotNamed` | No codebase of the load bears `name` |
| `NotGit` | The codebase `name` is hosted, so it has no commits to move between |
| `ScratchFailed` | The scratch could not be made, for `failure`, an `ActFailure`, its directory removed, or left in the temporary directory where that removal fails too |

The clone is cloned or fetched where it lacks the pin, so a scratch is made whatever the codebase's own outcome was. Another load or scratch acting on the clone is waited on, never acted beside.

## Using one

`scratch.package` is the `PackagePath` at the codebase's `root` inside the scratch. A scratch is handed out unresolved, and resolving it at a commit is the test's own work.

`scratch.move(commit)` takes it to any `Commit` of its URL's, which `Commit.parse` makes from a full hash and gives null for anything else, fetching the clone first where it lacks the commit, and returns a `Move`:

| Case | Means |
|---|---|
| `Moved` | The scratch holds that commit's tracked files alone: every edit to a tracked file reverted, and every other file removed, ignored ones among them |
| `MoveFailed` | The move failed for `failure`, an `ActFailure`, the scratch left where the failure left it |

No checkout is touched by a move.

## Disposing of one

`scratch.dispose()` removes the scratch's directory and its clone's record of it, and returns a `Disposal`:

| Case | Means |
|---|---|
| `Disposed` | The scratch is gone, and is again on a second disposal |
| `DisposalFailed` | The disposal failed for `failure`, an `ActFailure`, part of the scratch perhaps still there |

A scratch never disposed of stays in the temporary directory, so a test disposes of each in its tear-down.

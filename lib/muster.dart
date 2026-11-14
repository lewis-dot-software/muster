/// Brings the real codebases a tool tests against to their pins, resolved,
/// so a tool's `dart test` loads them with no setup.
///
/// A consumer names its codebases in a `muster.yaml` at its root, each by its
/// git URL, its commit, its root inside the repo and its toolchain, or by a
/// package on pub.dev at its version, and further manifests by
/// `MUSTER_MANIFESTS`. [Muster.load] clones each URL once into a cache every
/// consumer on the machine shares, checks each git codebase out and unpacks
/// each hosted one under the consumer's `.dart_tool/muster/`, resolves it on
/// its lock, and gives each a [FetchOutcome], every failure among them a
/// value.
/// [Muster.scratch] gives a consumer that must move a codebase off its pin a
/// worktree of its own to move, in a temporary directory.
library;

export 'src/load/load.dart' show Load, Loaded, Refused;
export 'src/load/muster.dart' show Muster;
export 'src/load/scratch.dart' show Scratch;
export 'src/load/scratching.dart'
    show Scratching, Scratched, NotNamed, NotGit, ScratchFailed;
export 'src/model/codebase_name.dart' show CodebaseName;
export 'src/model/command.dart' show Command;
export 'src/model/disposal.dart' show Disposal, Disposed, DisposalFailed;
export 'src/model/commit.dart' show Commit;
export 'src/model/executable.dart' show Executable;
export 'src/model/fetch_outcome.dart'
    show
        FetchOutcome,
        Fetched,
        FetchFailure,
        ActFailure,
        CommandFailed,
        Unstartable,
        StoreFailed,
        PinMissing,
        Unlocked;
export 'src/model/git_url.dart' show GitUrl;
export 'src/model/kept_lock_path.dart' show KeptLockPath;
export 'src/model/key_path.dart' show KeyPath;
export 'src/model/load_refusal.dart'
    show
        LoadRefusal,
        NoManifest,
        NotManifestName,
        ManifestMissing,
        ManifestUnreadable,
        ManifestInvalid,
        CodebaseNamedTwice,
        NoWorkingDirectory,
        NoCache,
        NoClaim;
export 'src/model/lock_path.dart' show LockPath;
export 'src/model/manifest_path.dart' show ManifestPath;
export 'src/model/move.dart' show Move, Moved, MoveFailed;
export 'src/model/os.dart' show Os;
export 'src/model/package_config_path.dart' show PackageConfigPath;
export 'src/model/manifest_refusal.dart'
    show
        ManifestRefusal,
        NotYaml,
        UnknownKey,
        MissingKey,
        MissingKind,
        BadValue;
export 'src/model/package_path.dart' show PackagePath;
export 'src/model/pubspec_overrides_path.dart' show PubspecOverridesPath;
export 'src/model/pubspec_path.dart' show PubspecPath;
export 'src/model/sdk_version.dart' show SdkVersion;
export 'src/model/wanted.dart' show Wanted;
export 'src/model/written.dart'
    show Written, WrittenText, WrittenList, WrittenMapping, WrittenNothing;

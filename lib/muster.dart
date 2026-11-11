/// Brings the real codebases a tool tests against to their pins, resolved,
/// so a tool's `dart test` loads them with no setup.
///
/// A consumer names its codebases in a `muster.yaml` at its root, each by its
/// git URL, its commit, its root inside the repo and its toolchain, and
/// further manifests by `MUSTER_MANIFESTS`. [Muster.load] clones each URL
/// once into a cache every consumer on the machine shares, checks each
/// codebase out under the consumer's `.dart_tool/muster/`, resolves it on its
/// lock, and gives each a [FetchOutcome], every failure among them a value.
library;

export 'src/load/load.dart' show Load, Loaded, Refused;
export 'src/load/muster.dart' show Muster;
export 'src/model/codebase_name.dart' show CodebaseName;
export 'src/model/command.dart' show Command;
export 'src/model/commit.dart' show Commit;
export 'src/model/executable.dart' show Executable;
export 'src/model/fetch_outcome.dart'
    show
        FetchOutcome,
        Fetched,
        FetchFailure,
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
        NoCache;
export 'src/model/lock_path.dart' show LockPath;
export 'src/model/manifest_path.dart' show ManifestPath;
export 'src/model/os.dart' show Os;
export 'src/model/package_config_path.dart' show PackageConfigPath;
export 'src/model/manifest_refusal.dart'
    show ManifestRefusal, NotYaml, UnknownKey, MissingKey, BadValue;
export 'src/model/package_path.dart' show PackagePath;
export 'src/model/sdk_version.dart' show SdkVersion;
export 'src/model/wanted.dart' show Wanted;

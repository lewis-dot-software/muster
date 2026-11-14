/// What muster reads of an unpacked package's `pubspec.yaml`: whether it
/// makes the package a [member] of a pub workspace, `resolution: workspace`,
/// and whether it [overrides] dependencies, holding `dependency_overrides`.
typedef PublishedPubspec = ({bool member, bool overrides});

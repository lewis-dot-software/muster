/// A manifest a load looks for: its absolute [path], and whether it was
/// [named], by the load's caller or `MUSTER_MANIFESTS`, or is the root's
/// `muster.yaml`, which no one named.
typedef ManifestSought = ({String path, bool named});

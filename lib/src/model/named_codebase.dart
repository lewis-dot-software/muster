import 'git_codebase.dart';

/// A codebase beside the manifest that named it: the [codebase], and the
/// index of its [manifest] among the load's.
typedef NamedCodebase = ({GitCodebase codebase, int manifest});

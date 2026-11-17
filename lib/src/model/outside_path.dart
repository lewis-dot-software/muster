import 'package_name.dart';

/// A path dependency of a hosted package's example that leaves the package,
/// absolute or climbing above its top, so pub does not serve it: the
/// `dependency` it names, and its `path` as the example's pubspec writes it.
typedef OutsidePath = ({PackageName dependency, String path});

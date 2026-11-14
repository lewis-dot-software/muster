import 'package_name.dart';

/// A path dependency of a hosted package's example that leaves the package,
/// on a sibling in its publisher's repo that pub does not serve: the
/// [dependency] it names, and its [path] as the example's pubspec writes it.
typedef OutsidePath = ({PackageName dependency, String path});

import 'package_path.dart';
import 'sdk_version.dart';

/// A codebase brought to its pin and resolved: the [package] to hand a tool,
/// and the [sdk] that resolved it.
typedef Checkout = ({PackagePath package, SdkVersion sdk});

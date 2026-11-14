import 'example.dart';
import 'package_path.dart';
import 'sdk_version.dart';

/// A codebase brought to its pin and resolved: the [package] to hand a tool,
/// what was made of its [example], and the [sdk] that resolved it.
typedef Checkout = ({PackagePath package, Example example, SdkVersion sdk});

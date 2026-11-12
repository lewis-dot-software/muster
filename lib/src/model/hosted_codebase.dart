import 'codebase_name.dart';
import 'package_name.dart';
import 'package_version.dart';
import 'resolution.dart';
import 'toolchain.dart';

/// A codebase a manifest names by a package on pub.dev: its [name], the
/// [package] it fetches, the [version] it is pinned at, its [resolution], and
/// the [toolchain] that resolves it.
typedef HostedCodebase = ({
  CodebaseName name,
  PackageName package,
  PackageVersion version,
  Resolution resolution,
  Toolchain toolchain,
});

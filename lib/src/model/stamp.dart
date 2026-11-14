import 'codebase.dart';
import 'outside_path.dart';
import 'package.dart';
import 'sdk_version.dart';
import 'stamped_package.dart';

/// The record a checkout carries of what resolved it: the [codebase] as its
/// manifest names it, every value the resolve turns on among its own, each
/// of its [packages] with its lock and the package config it wrote, the
/// root's always among them, the path dependency that left its example
/// [unresolved], null where none did and never beside a stamped example,
/// and the [sdk] that resolved it.
typedef Stamp = ({
  Codebase codebase,
  Map<Package, StampedPackage> packages,
  OutsidePath? unresolved,
  SdkVersion sdk,
});

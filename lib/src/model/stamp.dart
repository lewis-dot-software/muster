import 'commit.dart';
import 'git_url.dart';
import 'package.dart';
import 'repo_root.dart';
import 'sdk_version.dart';
import 'stamped_package.dart';
import 'toolchain.dart';

/// The record a checkout carries of what resolved it: every manifest value
/// the resolve turns on, the [url], [commit], [root] and [toolchain], each of
/// its [packages] with its lock and the package config it wrote, the root's
/// always among them, and the [sdk] that resolved it.
typedef Stamp = ({
  GitUrl url,
  Commit commit,
  RepoRoot root,
  Toolchain toolchain,
  Map<Package, StampedPackage> packages,
  SdkVersion sdk,
});

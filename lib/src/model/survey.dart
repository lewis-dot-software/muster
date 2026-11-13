import 'package.dart';
import 'sdk_version.dart';
import 'stamp.dart';
import 'surveyed_package.dart';
import 'worktree.dart';

/// What is read of one codebase's checkout: the [sdk] its toolchain on
/// `PATH` runs, the [stamp] beside it, null where there is none or it holds
/// no stamp, its git [worktree], null where there is none, git cannot read
/// it, no stamp is there to weigh it against or the codebase is hosted,
/// whether the package it hands out is [there], holding its `pubspec.yaml`,
/// and each of its [packages], every [Package] among them.
typedef Survey = ({
  SdkVersion sdk,
  Stamp? stamp,
  Worktree? worktree,
  bool there,
  Map<Package, SurveyedPackage> packages,
});

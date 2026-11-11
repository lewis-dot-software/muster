import 'package.dart';
import 'sdk_version.dart';
import 'stamp.dart';
import 'surveyed_package.dart';
import 'worktree.dart';

/// What is read of one codebase's checkout: the [sdk] its toolchain on
/// `PATH` runs, the [stamp] beside it, null where there is none or it holds
/// no stamp, its git [worktree], null where there is none, git cannot read
/// it or no stamp is there to weigh it against, and each of its [packages], every [Package] among them.
typedef Survey = ({
  SdkVersion sdk,
  Stamp? stamp,
  Worktree? worktree,
  Map<Package, SurveyedPackage> packages,
});

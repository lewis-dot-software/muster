import '../model/command.dart';
import '../model/fetch_outcome.dart';
import '../model/sdk_version.dart';
import '../model/toolchain.dart';
import 'ran.dart';
import 'runner.dart';
import 'store_fault.dart';

/// The version of each toolchain's SDK on `PATH`, its version command run by
/// a [Runner] the first time it is asked for, and its answer, or its
/// failure, given again from then on.
class SdkVersions {
  /// The versions read by [_runner].
  SdkVersions(this._runner);

  final Runner _runner;

  final Map<Toolchain, Future<SdkVersion>> _read = {};

  /// The version of [toolchain]'s SDK on `PATH`.
  ///
  /// Throws a [StoreFault] of [CommandFailed] where its version command
  /// fails or writes no version, and of [Unstartable] where the toolchain
  /// cannot start.
  Future<SdkVersion> of(Toolchain toolchain) =>
      _read[toolchain] ??= _version(toolchain);

  Future<SdkVersion> _version(Toolchain toolchain) async {
    final Command command = toolchain.version;
    final Ran ran = await _runner.run(command);
    return .read(toolchain, ran.stdout) ??
        (throw StoreFault(
          CommandFailed(command, ran.exitCode, ran.stdout, ran.stderr),
        ));
  }
}

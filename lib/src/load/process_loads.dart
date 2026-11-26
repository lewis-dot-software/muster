import '../model/environment.dart';
import '../model/load_refusal.dart';
import '../model/os.dart';
import '../model/working_directory.dart';
import '../store/current_directory.dart';
import '../store/locker.dart';
import '../store/process_environment.dart';
import '../store/process_system.dart';
import '../store/runner.dart';
import '../store/store_fault.dart';
import '../store/system_temp.dart';
import 'load.dart';
import 'loader.dart';
import 'loads.dart';
import 'locking.dart';
import 'refusal.dart';

/// The runs of the process muster runs in: its environment, its system, its
/// working directory and its temporary directory read once per run, at its
/// start, and every process the run starts given that environment, less and
/// over the variables a [Runner] names.
final class ProcessLoads implements Loads {
  /// The runs of the process muster runs in: its environment read by
  /// [environment], its system's name by [system] and its working directory
  /// by [directory], and its processes run by the runner [runner] makes of
  /// that environment.
  const ProcessLoads({
    this._environment = processEnvironment,
    this._system = processSystem,
    this._directory = currentDirectory,
    this._runner = _runnerOf,
  });

  final Environment Function() _environment;

  final String Function() _system;

  final Future<WorkingDirectory> Function(Os os) _directory;

  final Runner Function(Environment environment) _runner;

  /// Returns [Refused] with [NoClaim] where muster takes no claim on the
  /// system, and with [NoWorkingDirectory] where the working directory
  /// cannot be read, before any process starts or any file is written, and
  /// otherwise what [Loader.load] gives.
  @override
  Future<Load> load({List<String> named = const [], String? root}) async {
    final Loader loader;
    try {
      loader = await _loader();
    } on Refusal catch (refused) {
      return Refused(refused.reason);
    }
    return loader.load(named: named, root: root);
  }

  /// Returns [LockRefused] with [NoClaim] where muster takes no claim on the
  /// system, and with [NoWorkingDirectory] where the working directory
  /// cannot be read, before any process starts or any file is written, and
  /// otherwise what [Loader.lock] gives.
  @override
  Future<Locking> lock({List<String> named = const []}) async {
    final Loader loader;
    try {
      loader = await _loader();
    } on Refusal catch (refused) {
      return LockRefused(refused.reason);
    }
    return loader.lock(named: named);
  }

  /// The loader of the process as it stands now.
  ///
  /// Throws a [Refusal] where muster takes no claim on the system or the
  /// working directory cannot be read.
  Future<Loader> _loader() async {
    final Environment environment = _environment();
    final String system = _system();
    final Locker locker =
        .of(environment.os, system) ?? (throw Refusal(NoClaim(system)));
    final WorkingDirectory directory;
    try {
      directory = await _directory(environment.os);
    } on StoreFault catch (fault) {
      throw Refusal(NoWorkingDirectory(fault.fileFailure.reason));
    }
    return .new(
      environment,
      directory,
      _runner(environment),
      .new(locker),
      systemTemp(environment.os),
    );
  }
}

/// The runner of every process a load in [environment] starts.
Runner _runnerOf(Environment environment) =>
    .new(environment.variables, environment.os);

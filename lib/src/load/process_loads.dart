import '../model/environment.dart';
import '../model/fetch_outcome.dart';
import '../model/load_refusal.dart';
import '../model/working_directory.dart';
import '../store/current_directory.dart';
import '../store/process_environment.dart';
import '../store/store_fault.dart';
import '../store/system_temp.dart';
import 'load.dart';
import 'loader.dart';
import 'loads.dart';
import 'locking.dart';

/// The runs of the process muster runs in: its environment, its working
/// directory and its temporary directory read once a run, at its start, and
/// every process the run starts given that environment alone.
final class ProcessLoads implements Loads {
  /// The runs of the process muster runs in.
  const ProcessLoads();

  /// Returns [Refused] with [NoWorkingDirectory] where the working directory
  /// cannot be read, before any process starts or any file is written, and
  /// otherwise what [Loader.load] gives.
  @override
  Future<Load> load({List<String> named = const [], String? root}) async {
    final Loader loader;
    try {
      loader = await _loader();
    } on _Unreadable catch (unreadable) {
      return Refused(unreadable.refusal);
    }
    return loader.load(named: named, root: root);
  }

  /// Returns [LockRefused] with [NoWorkingDirectory] where the working
  /// directory cannot be read, before any process starts or any file is
  /// written, and otherwise what [Loader.lock] gives.
  @override
  Future<Locking> lock({List<String> named = const []}) async {
    final Loader loader;
    try {
      loader = await _loader();
    } on _Unreadable catch (unreadable) {
      return LockRefused(unreadable.refusal);
    }
    return loader.lock(named: named);
  }

  /// The loader of the process as it stands now.
  ///
  /// Throws an [_Unreadable] where the working directory cannot be read.
  Future<Loader> _loader() async {
    final Environment environment = processEnvironment();
    final WorkingDirectory directory;
    try {
      directory = await currentDirectory(environment.os);
    } on StoreFault catch (fault) {
      if (fault.failure case StoreFailed(:final String reason)) {
        throw _Unreadable(NoWorkingDirectory(reason));
      }
      rethrow;
    }
    return Loader(
      environment,
      directory,
      .new(environment.variables),
      .new(environment.os),
      systemTemp(environment.os),
    );
  }
}

/// A working directory the system cannot give, refused for [refusal].
final class _Unreadable implements Exception {
  const _Unreadable(this.refusal);

  final NoWorkingDirectory refusal;
}

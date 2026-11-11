import '../model/clone_path.dart';
import '../model/command.dart';

/// Git's [arguments] on [clone], named by `--git-dir`, since git refuses a
/// bare repo found from a directory where `safe.bareRepository` is
/// `explicit`.
Command gitOn(ClonePath clone, List<String> arguments) =>
    (executable: .git, arguments: ['--git-dir=${clone.path}', ...arguments]);

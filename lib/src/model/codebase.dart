import 'codebase_name.dart';
import 'git_codebase.dart';
import 'hosted_codebase.dart';
import 'toolchain.dart';

/// A codebase a manifest names, by git or by a package on pub.dev.
sealed class Codebase {
  const Codebase();

  /// The codebase's name, its key in the manifest.
  CodebaseName get name => switch (this) {
    Git(:final GitCodebase codebase) => codebase.name,
    Hosted(:final HostedCodebase codebase) => codebase.name,
  };

  /// The toolchain that resolves the codebase.
  Toolchain get toolchain => switch (this) {
    Git(:final GitCodebase codebase) => codebase.toolchain,
    Hosted(:final HostedCodebase codebase) => codebase.toolchain,
  };
}

/// A codebase named by git.
final class Git extends Codebase {
  /// The codebase [codebase].
  const Git(this.codebase);

  /// The git codebase.
  final GitCodebase codebase;

  @override
  bool operator ==(Object other) => other is Git && other.codebase == codebase;

  @override
  int get hashCode => Object.hash(Git, codebase);

  @override
  String toString() => 'Git($codebase)';
}

/// A codebase named by a package on pub.dev.
final class Hosted extends Codebase {
  /// The codebase [codebase].
  const Hosted(this.codebase);

  /// The hosted codebase.
  final HostedCodebase codebase;

  @override
  bool operator ==(Object other) =>
      other is Hosted && other.codebase == codebase;

  @override
  int get hashCode => Object.hash(Hosted, codebase);

  @override
  String toString() => 'Hosted($codebase)';
}

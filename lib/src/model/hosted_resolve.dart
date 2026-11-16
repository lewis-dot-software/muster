import 'outside_path.dart';
import 'published_pubspec.dart';

/// What a hosted codebase does with one of its packages, as read from the
/// package unpacked.
sealed class HostedResolve {
  const HostedResolve();
}

/// A package resolved, its pubspec read as [published].
final class Resolves extends HostedResolve {
  /// The package resolved, its pubspec holding what [published] says.
  const Resolves(this.published);

  /// What muster reads of the package's pubspec.
  final PublishedPubspec published;

  @override
  bool operator ==(Object other) =>
      other is Resolves && other.published == published;

  @override
  int get hashCode => Object.hash(Resolves, published);

  @override
  String toString() => 'Resolves($published)';
}

/// An example left unresolved, since its path dependency [outside] leaves
/// the package.
final class LeftUnresolved extends HostedResolve {
  /// The example left unresolved for the path dependency [outside].
  const LeftUnresolved(this.outside);

  /// The path dependency that leaves the package.
  final OutsidePath outside;

  @override
  bool operator ==(Object other) =>
      other is LeftUnresolved && other.outside == outside;

  @override
  int get hashCode => Object.hash(LeftUnresolved, outside);

  @override
  String toString() => 'LeftUnresolved($outside)';
}

/// An example the package unpacked holds no pubspec for, so nothing
/// resolves it.
final class NotHeld extends HostedResolve {
  /// The example of a package that holds no pubspec for one.
  const NotHeld();

  @override
  bool operator ==(Object other) => other is NotHeld;

  @override
  int get hashCode => (NotHeld).hashCode;

  @override
  String toString() => 'NotHeld()';
}

import 'lock_source.dart';
import 'package.dart';

/// What choosing a codebase's locks gave: the lock each package resolves on,
/// or the package that has none.
sealed class LockChoice {
  const LockChoice();
}

/// A lock for every package.
final class LocksChosen extends LockChoice {
  /// The choice that gave each package in [locks] its lock's source.
  const LocksChosen(this.locks);

  /// Each package the codebase resolves, in [Package]'s order, beside where
  /// its lock comes from.
  final Map<Package, LockSource> locks;
}

/// A package with no lock.
final class LockLacking extends LockChoice {
  /// The choice that found [package] with no lock.
  const LockLacking(this.package);

  /// The first package, in [Package]'s order, that takes no lock its pin
  /// holds and has no kept lock.
  final Package package;
}

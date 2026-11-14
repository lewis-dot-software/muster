import 'outside_path.dart';
import 'package_path.dart';

/// What a checkout made of its codebase's example, the `example/` inside the
/// package it hands out.
sealed class Example {
  const Example();
}

/// A package that holds no example with a pubspec of its own.
final class NoExample extends Example {
  /// The example of a package that holds none.
  const NoExample();

  @override
  bool operator ==(Object other) => other is NoExample;

  @override
  int get hashCode => (NoExample).hashCode;

  @override
  String toString() => 'NoExample()';
}

/// An example resolved, as the package it hands out is.
final class ExampleResolved extends Example {
  /// The example resolved at [package].
  const ExampleResolved(this.package);

  /// The example's package, inside the checkout.
  final PackagePath package;

  @override
  bool operator ==(Object other) =>
      other is ExampleResolved && other.package == package;

  @override
  int get hashCode => Object.hash(ExampleResolved, package);

  @override
  String toString() => 'ExampleResolved(${package.path})';
}

/// An example left unresolved, since it cannot resolve as published.
final class ExampleUnresolved extends Example {
  /// The example left unresolved for the path dependency [outside].
  const ExampleUnresolved(this.outside);

  /// The path dependency that leaves the package.
  final OutsidePath outside;

  @override
  bool operator ==(Object other) =>
      other is ExampleUnresolved && other.outside == outside;

  @override
  int get hashCode => Object.hash(ExampleUnresolved, outside);

  @override
  String toString() => 'ExampleUnresolved($outside)';
}

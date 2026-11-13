import 'package.dart';

/// Whether a hosted codebase resolves its [package], [held] where the package
/// unpacked holds its pubspec: the root always, held or not, and the example
/// only where held.
bool hostedResolves(Package package, {required bool held}) => switch (package) {
  .root => true,
  .example => held,
};

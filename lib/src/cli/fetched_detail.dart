import '../model/example.dart';
import '../model/fetch_outcome.dart';
import '../model/package_name.dart';
import '../model/quoted.dart';

/// [fetched]'s detail, as its row's cell gives it: the path of the package
/// handed out, and where its example was left unresolved, the path
/// dependency that left it, its path quoted, so the cell holds one line and
/// no tab whatever the example's pubspec writes.
String fetchedDetail(Fetched fetched) => switch (fetched.example) {
  NoExample() || ExampleResolved() => fetched.package.path,
  ExampleUnresolved(
    outside: (:final PackageName dependency, :final String path),
  ) =>
    '${fetched.package.path} (example unresolved: ${dependency.name} at '
        '${quoted(path)})',
};

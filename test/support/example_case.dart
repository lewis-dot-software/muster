import 'package:muster/muster.dart';
import 'package:muster/src/model/consumer_root.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/package_path.dart';

/// A case of [Example], each named once in [of], so a case the type gains
/// fails the build until it is named here.
enum ExampleCase {
  /// [NoExample].
  none,

  /// [ExampleResolved].
  resolved,

  /// [ExampleUnresolved].
  unresolved;

  /// The case of [example].
  static ExampleCase of(Example example) => switch (example) {
    NoExample() => .none,
    ExampleResolved() => .resolved,
    ExampleUnresolved() => .unresolved,
  };

  /// An example of this case for [codebase]'s checkout under [root], left
  /// unresolved for `outside` at [outside] where it is [ExampleUnresolved].
  Example example(ConsumerRoot root, GitCodebase codebase, String outside) =>
      switch (this) {
        .none => const NoExample(),
        .resolved => ExampleResolved(
          packageIn(.of(root, codebase.name), codebase.root, .example),
        ),
        .unresolved => ExampleUnresolved((
          dependency: .parse('outside')!,
          path: outside,
        )),
      };
}

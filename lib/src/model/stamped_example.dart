import 'example.dart';
import 'outside_path.dart';
import 'package.dart';
import 'package_path.dart';
import 'stamp.dart';

/// What [stamp] records of its checkout's example, whose package is at
/// [example]: left unresolved where the stamp names why, resolved where the
/// stamp names its package, and else none.
Example stampedExample(Stamp stamp, PackagePath example) =>
    switch ((stamp.unresolved, stamp.packages.containsKey(Package.example))) {
      (final OutsidePath outside, _) => ExampleUnresolved(outside),
      (null, true) => ExampleResolved(example),
      (null, false) => const NoExample(),
    };

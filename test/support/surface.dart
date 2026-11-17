import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'loads.dart';

/// `lib/muster.dart`, the library a consumer imports, resolved by the
/// analyzer, failing the test where it does not resolve.
Future<LibraryElement> musterSurface() async {
  final String library = p.normalize(
    p.join(await musterRoot(), 'lib', 'muster.dart'),
  );
  final SomeResolvedLibraryResult resolved = await AnalysisContextCollection(
    includedPaths: [library],
  ).contextFor(library).currentSession.getResolvedLibrary(library);
  return switch (resolved) {
    ResolvedLibraryResult(:final LibraryElement element) => element,
    _ => fail('lib/muster.dart did not resolve: $resolved'),
  };
}

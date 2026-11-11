import 'content_hash.dart';

/// What a survey read of one package a codebase could resolve, each a hash
/// of the file's contents, or null where the file is not there: the [lock]
/// in the checkout's package, the [keptLock] beside its manifest, and the
/// [packageConfig] a resolve wrote in the package.
typedef SurveyedPackage = ({
  ContentHash? lock,
  ContentHash? keptLock,
  ContentHash? packageConfig,
});

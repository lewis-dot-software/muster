import 'clone_path.dart';

/// The directory a new clone is made in before it moves into place, beside
/// the clone it is made for.
extension type const TemporaryClonePath._(String path) {
  /// The temporary clone of [clone], its directory's name with `.partial`
  /// after it.
  static TemporaryClonePath of(ClonePath clone) =>
      ._('${clone.path}$temporaryCloneSuffix');
}

/// What a temporary clone's name holds after its clone's.
const String temporaryCloneSuffix = '.partial';

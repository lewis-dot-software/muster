import 'package.dart';

/// What a codebase's pin holds of its packages: the [packages] it resolves,
/// the root's always among them, and the packages among them that resolve on
/// the `pubspec.lock` it holds for them, [locked], none of a hosted
/// codebase's, whose locks are all kept whatever pub serves.
typedef AtCommit = ({Set<Package> packages, Set<Package> locked});

import 'package.dart';

/// What a codebase's pin holds of its packages: the [packages] it resolves,
/// the root's always among them, and the packages among them it holds a
/// `pubspec.lock` for, [locked], none of a hosted codebase's, whose locks
/// are all kept.
typedef AtCommit = ({Set<Package> packages, Set<Package> locked});

import 'package.dart';

/// What a git codebase's commit holds of its packages: the [packages] it
/// resolves, the root's always among them, and the packages among them it
/// holds a `pubspec.lock` for, [locked].
typedef AtCommit = ({Set<Package> packages, Set<Package> locked});

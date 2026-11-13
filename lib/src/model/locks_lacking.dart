import 'at_commit.dart';
import 'package.dart';

/// The packages [atCommit] holds that need a kept lock and are not among
/// [kept], in [Package]'s order: each whose pin holds no `pubspec.lock`.
List<Package> locksLacking(AtCommit atCommit, Set<Package> kept) => [
  for (final Package package in Package.values)
    if (atCommit.packages.contains(package) &&
        !atCommit.locked.contains(package) &&
        !kept.contains(package))
      package,
];

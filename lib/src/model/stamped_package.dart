import 'content_hash.dart';
import 'lock_source.dart';

/// What a stamp records of one package it resolved: the [source] of the
/// lock it resolved on, the hash of that [lock] as placed in the package, and
/// the hash of the [packageConfig] its resolve wrote.
typedef StampedPackage = ({
  LockSource source,
  ContentHash lock,
  ContentHash packageConfig,
});

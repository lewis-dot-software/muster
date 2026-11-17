import 'package:grit/grit.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/content_hash.dart';
import 'package:muster/src/model/lock_source.dart';
import 'package:muster/src/model/outside_path.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/sdk_version.dart';
import 'package:muster/src/model/stamp.dart';
import 'package:muster/src/model/stamped_package.dart';
import 'package:test/test.dart';

import 'manifests.dart';

/// The stamp of [codebase], its [packages] resolved by [sdk], its example
/// left [unresolved] for the path dependency named, where one is.
Stamp stampOf(
  Codebase codebase,
  Map<Package, StampedPackage> packages,
  SdkVersion sdk, {
  OutsidePath? unresolved,
}) =>
    (codebase: codebase, packages: packages, unresolved: unresolved, sdk: sdk);

/// Matches a stamp whose every value is [stamp]'s, its packages compared
/// entry by entry.
Matcher sameStamp(Stamp stamp) => isA<Stamp>()
    .having((Stamp s) => s.codebase, 'codebase', stamp.codebase)
    .having((Stamp s) => s.packages, 'packages', equals(stamp.packages))
    .having((Stamp s) => s.unresolved, 'unresolved', stamp.unresolved)
    .having((Stamp s) => s.sdk, 'sdk', stamp.sdk);

/// A file's hash.
final Gen<ContentHash> anyContentHash = hexOfLength(64)
    .map((String hex) => .parse(hex)!);

/// An SDK's version.
final Gen<SdkVersion> anySdkVersion = .build(
  (Draw draw) => .parse(
    '${draw(.integer(min: 0, max: 19))}.${draw(.integer(min: 0, max: 19))}.0'
    '${draw(.element(['', '-0.1.pre', '+hotfix.1']))}',
  )!,
);

/// What a stamp records of one package.
final Gen<StampedPackage> anyStampedPackage = .build(
  (Draw draw) => (
    source: draw(.element(LockSource.values)),
    lock: draw(anyContentHash),
    packageConfig: draw(anyContentHash),
  ),
);

/// A stamp's packages, the root's always among them and the example's
/// drawn or not.
final Gen<Map<Package, StampedPackage>> anyStampedPackages = .build(
  (Draw draw) => {
    .root: draw(anyStampedPackage),
    if (draw(.boolean())) .example: draw(anyStampedPackage),
  },
);

/// A path dependency that leaves its package, its path any text, line
/// breaks and quotes among it.
final Gen<OutsidePath> anyOutsidePath = .build((Draw draw) {
  final String dependency = draw(.element(['b', 'freezed_annotation', 'a.b']));
  final String odd = draw(.element(['', '\n', '\t', '"', r'\', '\u2028']));
  return (dependency: .parse(dependency)!, path: '../../$dependency$odd');
});

/// A stamp of any codebase, of either kind, its example left unresolved
/// or not where it stamps none.
final Gen<Stamp> anyStamp = .build((Draw draw) {
  final Codebase codebase = draw(anyCodebase());
  final Map<Package, StampedPackage> packages = draw(anyStampedPackages);
  final SdkVersion sdk = draw(anySdkVersion);
  final OutsidePath? outside = draw(
    .oneOf([
      .element([null]),
      anyOutsidePath,
    ]),
  );
  return stampOf(
    codebase,
    packages,
    sdk,
    unresolved: packages.containsKey(Package.example) ? null : outside,
  );
});

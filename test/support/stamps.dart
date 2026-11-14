import 'package:glados/glados.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/content_hash.dart';
import 'package:muster/src/model/lock_source.dart';
import 'package:muster/src/model/outside_path.dart';
import 'package:muster/src/model/package.dart';
import 'package:muster/src/model/package_name.dart';
import 'package:muster/src/model/sdk_version.dart';
import 'package:muster/src/model/stamp.dart';
import 'package:muster/src/model/stamped_package.dart';

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

/// The generators the stamp's property tests draw from.
extension StampAnys on Any {
  /// A file's hash.
  Generator<ContentHash> get contentHash =>
      hexOfLength(64).map((String hex) => .parse(hex)!);

  /// An SDK's version.
  Generator<SdkVersion> get sdkVersion => combine3(
    intInRange(0, 20),
    intInRange(0, 20),
    choose(['', '-0.1.pre', '+hotfix.1']),
    (int major, int minor, String tail) => .parse('$major.$minor.0$tail')!,
  );

  /// What a stamp records of one package.
  Generator<StampedPackage> get stampedPackage => combine3(
    choose(LockSource.values),
    contentHash,
    contentHash,
    (LockSource source, ContentHash lock, ContentHash config) =>
        (source: source, lock: lock, packageConfig: config),
  );

  /// A stamp's packages, the root's always among them and the example's
  /// drawn or not.
  Generator<Map<Package, StampedPackage>> get stampedPackages => combine3(
    stampedPackage,
    stampedPackage,
    this.bool,
    (StampedPackage root, StampedPackage example, bool hasExample) => {
      .root: root,
      if (hasExample) .example: example,
    },
  );

  /// A path dependency that leaves its package, its path any text, line
  /// breaks and quotes among it.
  Generator<OutsidePath> get outsidePath => combine2(
    choose(['b', 'freezed_annotation', 'a.b']),
    choose(['', '\n', '\t', '"', r'\', '\u2028']),
    (String dependency, String odd) => (
      dependency: PackageName.parse(dependency)!,
      path: '../../$dependency$odd',
    ),
  );

  /// A stamp of any codebase, of either kind, its example left unresolved
  /// or not where it stamps none.
  Generator<Stamp> get stamp => combine4(
    anyCodebase(),
    stampedPackages,
    sdkVersion,
    outsidePath.nullable,
    (
      Codebase codebase,
      Map<Package, StampedPackage> packages,
      SdkVersion sdk,
      OutsidePath? outside,
    ) => stampOf(
      codebase,
      packages,
      sdk,
      unresolved: packages.containsKey(Package.example) ? null : outside,
    ),
  );
}

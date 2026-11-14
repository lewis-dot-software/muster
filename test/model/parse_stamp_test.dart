import 'dart:convert';

import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/content_hash.dart';
import 'package:muster/src/model/parse_stamp.dart';
import 'package:muster/src/model/render_stamp.dart';
import 'package:muster/src/model/stamp.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';
import '../support/stamps.dart';

void main() {
  final ContentHash hash = .of([1]);

  final Stamp git = stampOf(
    Git(codebase('app', 'https://example.com/app.git', 'a' * 40, '.', .dart)),
    {.root: (source: .committed, lock: hash, packageConfig: hash)},
    .parse('3.13.7')!,
  );

  final Stamp hostedStamp = stampOf(
    Hosted(hosted('dio', 'dio', '5.9.0', .asDependency, .flutter)),
    {
      .root: (source: .kept, lock: hash, packageConfig: hash),
      .example: (source: .kept, lock: hash, packageConfig: hash),
    },
    .parse('3.38.1')!,
  );

  /// [stamp]'s JSON object, as `renderStamp` writes it.
  Map<String, Object?> jsonOf(Stamp stamp) =>
      jsonDecode(renderStamp(stamp)) as Map<String, Object?>;

  test('a stamp of either kind as written is read back', () {
    for (final Stamp stamp in [git, hostedStamp]) {
      expect(parseStamp(jsonEncode(jsonOf(stamp))), sameStamp(stamp));
    }
  });

  test('a hosted stamp of a package pub takes but no codebase name fits is '
      'read back', () {
    for (final String package in ['_fe_analyzer_shared', 'Dio', 'a.b']) {
      final Stamp stamp = stampOf(
        Hosted(hosted('dio', package, '5.9.0', .alone, .dart)),
        {.root: (source: .kept, lock: hash, packageConfig: hash)},
        .parse('3.13.7')!,
      );
      expect(
        parseStamp(jsonEncode(jsonOf(stamp))),
        sameStamp(stamp),
        reason: package,
      );
    }
  });

  test('a hosted stamp names its package, version and resolution', () {
    expect(jsonOf(hostedStamp), {
      'name': 'dio',
      'hosted': 'dio',
      'version': '5.9.0',
      'resolution': 'as-dependency',
      'toolchain': 'flutter',
      'sdk': '3.38.1',
      'packages': {
        'root': {'source': 'kept', 'lock': hash.hex, 'packageConfig': hash.hex},
        'example': {
          'source': 'kept',
          'lock': hash.hex,
          'packageConfig': hash.hex,
        },
      },
    });
  });

  test('text that holds no stamp reads as none', () {
    final Map<String, Object?> rootless = jsonOf(git)
      ..['packages'] = <String, Object?>{};
    final Map<String, Object?> extra = jsonOf(git)..['depth'] = 1;
    final Map<String, Object?> nameless = jsonOf(git)..remove('name');
    final Map<String, Object?> badName = jsonOf(git)..['name'] = 'App';
    final Map<String, Object?> badHash = jsonOf(git)
      ..['packages'] = {
        'root': {'source': 'kept', 'lock': 'abc', 'packageConfig': hash.hex},
      };
    final Map<String, Object?> unknownPackage = jsonOf(git)
      ..['packages'] = {
        'root': {'source': 'kept', 'lock': hash.hex, 'packageConfig': hash.hex},
        'docs': {'source': 'kept', 'lock': hash.hex, 'packageConfig': hash.hex},
      };
    final Map<String, Object?> badToolchain = jsonOf(git)..['toolchain'] = 'go';
    final Map<String, Object?> bothKinds = {
      ...jsonOf(git),
      'hosted': 'dio',
      'version': '5.9.0',
      'resolution': 'alone',
    };
    final Map<String, Object?> gitAndVersion = jsonOf(git)
      ..remove('root')
      ..['version'] = '5.9.0';
    final Map<String, Object?> badVersion = jsonOf(hostedStamp)
      ..['version'] = 'five';
    final Map<String, Object?> badResolution = jsonOf(hostedStamp)
      ..['resolution'] = 'asDependency';
    final Map<String, Object?> badPackage = jsonOf(hostedStamp)
      ..['hosted'] = 'my-dio';
    final Map<String, Object?> reservedPackage = jsonOf(hostedStamp)
      ..['hosted'] = 'class';
    for (final String text in [
      '',
      'not json',
      '[]',
      jsonEncode(rootless),
      jsonEncode(extra),
      jsonEncode(nameless),
      jsonEncode(badName),
      jsonEncode(badHash),
      jsonEncode(unknownPackage),
      jsonEncode(badToolchain),
      jsonEncode(bothKinds),
      jsonEncode(gitAndVersion),
      jsonEncode(badVersion),
      jsonEncode(badResolution),
      jsonEncode(badPackage),
      jsonEncode(reservedPackage),
    ]) {
      expect(parseStamp(text), isNull, reason: text);
    }
  });
}

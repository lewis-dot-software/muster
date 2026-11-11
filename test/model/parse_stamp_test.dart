import 'dart:convert';

import 'package:muster/src/model/content_hash.dart';
import 'package:muster/src/model/parse_stamp.dart';
import 'package:muster/src/model/render_stamp.dart';
import 'package:test/test.dart';

import '../support/manifests.dart';
import '../support/stamps.dart';

void main() {
  final ContentHash hash = .of([1]);

  /// A stamp's JSON object, as `renderStamp` writes one.
  Map<String, Object?> stampJson() => jsonDecode(
    renderStamp(
      stampOf(
        codebase('app', 'https://example.com/app.git', 'a' * 40, '.', .dart),
        {.root: (source: .committed, lock: hash, packageConfig: hash)},
        .parse('3.13.7')!,
      ),
    ),
  ) as Map<String, Object?>;

  test('a stamp as written is read back', () {
    expect(parseStamp(jsonEncode(stampJson())), isNotNull);
  });

  test('text that holds no stamp reads as none', () {
    final Map<String, Object?> rootless = stampJson()
      ..['packages'] = <String, Object?>{};
    final Map<String, Object?> extra = stampJson()..['depth'] = 1;
    final Map<String, Object?> badHash = stampJson()
      ..['packages'] = {
        'root': {'source': 'kept', 'lock': 'abc', 'packageConfig': hash.hex},
      };
    final Map<String, Object?> unknownPackage = stampJson()
      ..['packages'] = {
        'root': {'source': 'kept', 'lock': hash.hex, 'packageConfig': hash.hex},
        'docs': {'source': 'kept', 'lock': hash.hex, 'packageConfig': hash.hex},
      };
    final Map<String, Object?> badToolchain = stampJson()..['toolchain'] = 'go';
    for (final String text in [
      '',
      'not json',
      '[]',
      jsonEncode(rootless),
      jsonEncode(extra),
      jsonEncode(badHash),
      jsonEncode(unknownPackage),
      jsonEncode(badToolchain),
    ]) {
      expect(parseStamp(text), isNull, reason: text);
    }
  });
}

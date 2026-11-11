import 'package:muster/src/model/manifest_parse.dart';
import 'package:muster/src/model/manifest_refusal.dart';
import 'package:muster/src/model/wanted.dart';
import 'package:test/test.dart';

import 'manifests.dart';

/// Matches a parse refused for [refusal].
Matcher refused(Matcher refusal) => isA<ManifestRefused>().having(
  (ManifestRefused parse) => parse.refusal,
  'refusal',
  refusal,
);

/// Matches a parse refused on the unknown key at [keys].
Matcher unknownKey(List<String> keys) => refused(
  isA<UnknownKey>().having((UnknownKey r) => r.path, 'path', pathOf(keys)),
);

/// Matches a parse refused on the missing key at [keys].
Matcher missingKey(List<String> keys) => refused(
  isA<MissingKey>().having((MissingKey r) => r.path, 'path', pathOf(keys)),
);

/// Matches a parse refused on the value at [keys], which must be [wanted].
Matcher badValue(List<String> keys, Wanted wanted) => refused(
  isA<BadValue>()
      .having((BadValue r) => r.path, 'path', pathOf(keys))
      .having((BadValue r) => r.wanted, 'wanted', wanted),
);

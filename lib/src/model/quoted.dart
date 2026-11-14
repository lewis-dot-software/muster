import 'dart:convert';

/// [text] quoted as a JSON string, so it reads on one line: each character
/// that breaks a line escaped, the ones `jsonEncode` leaves as they stand
/// among them.
String quoted(String text) => jsonEncode(text).replaceAllMapped(
  _unescaped,
  (Match match) =>
      '\\u${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
);

/// What `jsonEncode` writes as it stands of the characters that break a
/// line.
final RegExp _unescaped = .new(r'[\x7f-\x9f\u2028\u2029]');

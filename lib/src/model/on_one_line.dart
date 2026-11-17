import 'breaks_line.dart';
import 'quoted.dart';

/// [text] as it stands, or quoted where it holds a character that breaks a
/// line, so it never breaks the line it is set in.
String onOneLine(String text) => breaksLine(text) ? quoted(text) : text;

import '../model/breaks_line.dart';
import '../model/quoted.dart';

/// [text] as a row's cell gives it: as it stands, or quoted, each tab and
/// each character that breaks a line escaped, where it holds one or opens on
/// `"`, so the cell holds one line and no tab, and a quoted cell reads apart
/// from one that stands.
String cell(String text) =>
    text.startsWith('"') || text.contains('\t') || breaksLine(text)
    ? quoted(text)
    : text;

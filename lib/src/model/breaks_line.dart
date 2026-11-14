/// Whether [text] holds a character that breaks a line: a control character
/// but a tab, or a line break Unicode names.
bool breaksLine(String text) => text.contains(_breaking);

/// Every control character but a tab, and Unicode's line breaks beyond them.
final RegExp _breaking = .new(r'[\x00-\x08\x0a-\x1f\x7f-\x9f\u2028\u2029]');

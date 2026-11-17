import 'breaks_line.dart';

/// The URL a git codebase is cloned from, as written in its manifest.
extension type const GitUrl._(String url) {
  /// The URL [text] is, or null where it is empty, opens on `-`, which git
  /// would read as an option, or holds a control character but a tab, or
  /// Unicode's line or paragraph separator, which no URL holds.
  static GitUrl? parse(String text) =>
      text.isEmpty || text.startsWith('-') || breaksLine(text)
      ? null
      : ._(text);
}

/// The URL a git codebase is cloned from, as written in its manifest.
extension type const GitUrl._(String url) {
  /// The URL [text] is, or null where it is empty or opens on `-`, which git
  /// would read as an option.
  static GitUrl? parse(String text) =>
      text.isEmpty || text.startsWith('-') ? null : ._(text);
}

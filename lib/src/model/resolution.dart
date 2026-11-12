/// How a hosted package resolves.
enum Resolution {
  /// As its own `pub get` would, its dev dependencies among its packages.
  alone('alone'),

  /// As the dependency of a package around it, its dev dependencies left
  /// out.
  asDependency('as-dependency');

  const Resolution(this.word);

  /// The word a manifest writes for the resolution.
  final String word;

  /// The resolution [text] is the word of, or null where it is none.
  static Resolution? parse(String text) => _byWord[text];

  static final Map<String, Resolution> _byWord = {
    for (final Resolution resolution in values) resolution.word: resolution,
  };
}

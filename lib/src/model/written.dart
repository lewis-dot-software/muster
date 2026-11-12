/// What a manifest writes where a value refused: a plain value's text, or
/// the kind of value it is where it is no plain value.
sealed class Written {
  const Written();
}

/// A plain value, as the manifest writes it, its quotes among it.
final class WrittenText extends Written {
  /// The plain value written [text].
  const WrittenText(this.text);

  /// The value's text, as the manifest writes it.
  final String text;
}

/// A list.
final class WrittenList extends Written {
  /// A list written.
  const WrittenList();
}

/// A mapping.
final class WrittenMapping extends Written {
  /// A mapping written.
  const WrittenMapping();
}

/// Nothing at all, as an empty manifest or a key with no value writes.
final class WrittenNothing extends Written {
  /// Nothing written.
  const WrittenNothing();
}

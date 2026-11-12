/// What the cache reads of a URL's clone before each act on it.
enum CloneState {
  /// No clone of the URL is there.
  missing,

  /// The clone is there, lacking the pin's commit.
  lacking,

  /// The clone is there, holding the pin's commit.
  holding,
}

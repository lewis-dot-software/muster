/// The act the cache takes next on a URL's clone, toward one holding the
/// pin's commit.
enum CloneStep {
  /// The URL cloned afresh.
  clone,

  /// Every branch and tag of the URL fetched into the clone.
  fetch,

  /// The clone handed out untouched.
  use,

  /// The pin's commit on none of the URL's branches or tags.
  pinMissing,
}

/// Where a contender runs apart from its test.
enum Apart {
  /// An isolate of the test's process, in a group of its own, as `dart test`
  /// runs each test file.
  isolate,

  /// A process of its own, as `flutter test` runs each test file.
  process,
}

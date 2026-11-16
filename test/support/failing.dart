/// A call of the C library made to fail, leaving [errno] in `errno`, its
/// first calls alone where a count is given, or every call where none is.
final class Failing {
  /// A call failing with [errno], its first [calls] alone where that is given.
  Failing(this.errno, [this._left]);

  /// What each failed call leaves in `errno`.
  final int errno;

  /// How many calls are left to fail, null where every call fails.
  int? _left;

  /// Whether the call made now fails.
  bool get fails {
    switch (_left) {
      case null:
        return true;
      case 0:
        return false;
      case final int left:
        _left = left - 1;
        return true;
    }
  }
}

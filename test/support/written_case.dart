import 'package:muster/src/model/written.dart';

/// A case of [Written], each named once in [of], so a case the type gains
/// fails the build until it is named here.
enum WrittenCase {
  /// [WrittenText].
  text,

  /// [WrittenList].
  list,

  /// [WrittenMapping].
  mapping,

  /// [WrittenNothing].
  nothing;

  /// The case of [written].
  static WrittenCase of(Written written) => switch (written) {
    WrittenText() => .text,
    WrittenList() => .list,
    WrittenMapping() => .mapping,
    WrittenNothing() => .nothing,
  };

  /// A value of this case.
  Written get sample => switch (this) {
    .text => const WrittenText('go'),
    .list => const WrittenList(),
    .mapping => const WrittenMapping(),
    .nothing => const WrittenNothing(),
  };
}

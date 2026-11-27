import 'package:grit/grit.dart';

/// Every order of [items], each item once, drawn as a shuffle that takes each
/// next item at random from those left.
Gen<List<T>> orderOf<T>(List<T> items) => .build((Draw draw) {
  final List<T> left = .of(items);
  return [
    for (int i = 0; i < items.length; i++)
      left.removeAt(draw(.integer(min: 0, max: left.length - 1))),
  ];
});

import 'package:grit/grit.dart';
import 'package:test/test.dart';

import 'order_of.dart';

void main() {
  property('An order of any items holds each of them as often as the items do, '
      'and no other.', (Draw draw) {
    final List<int> items = draw(
      .list(.integer(min: 0, max: 3), maxLength: 7),
      label: 'items',
    );
    final List<int> order = draw(orderOf(items), label: 'order');
    expect(order, unorderedEquals(items));
  });
}

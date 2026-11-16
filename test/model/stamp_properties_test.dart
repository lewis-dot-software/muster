import 'package:grit/grit.dart';
import 'package:muster/src/model/parse_stamp.dart';
import 'package:muster/src/model/render_stamp.dart';
import 'package:muster/src/model/stamp.dart';
import 'package:test/test.dart';

import '../support/stamps.dart';

void main() {
  property('A stamp written and then read gives back the values it was written '
      'from.', (Draw draw) {
    final Stamp stamp = draw(anyStamp, label: 'stamp');
    expect(parseStamp(renderStamp(stamp)), sameStamp(stamp));
  });
}

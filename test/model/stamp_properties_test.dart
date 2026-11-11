import 'package:glados/glados.dart';
import 'package:muster/src/model/parse_stamp.dart';
import 'package:muster/src/model/render_stamp.dart';
import 'package:muster/src/model/stamp.dart';

import '../support/stamps.dart';

void main() {
  Glados(any.stamp).test(
    'A stamp written and then read gives back the values it was written '
    'from.',
    (Stamp stamp) {
      expect(parseStamp(renderStamp(stamp)), sameStamp(stamp));
    },
  );
}

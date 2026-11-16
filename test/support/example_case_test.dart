import 'package:muster/src/model/consumer_root.dart';
import 'package:test/test.dart';

import 'example_case.dart';
import 'manifests.dart';

void main() {
  test('every case makes an example of its own case', () {
    for (final ExampleCase kind in ExampleCase.values) {
      expect(
        ExampleCase.of(
          kind.example(
            ConsumerRoot('/consumer', .posix),
            codebase('app', '/srv/app.git', 'a' * 40, '.', .dart),
            '../outside',
          ),
        ),
        kind,
      );
    }
  });
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'chmod.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
  });

  tearDown(() => temp.delete(recursive: true));

  test('a mode chmod sets is the one the file holds after', () async {
    final File file = await .new(p.join(temp.path, 'file')).writeAsString('');
    await chmod('500', file);
    expect((await file.stat()).mode & 511, int.parse('500', radix: 8));
  });

  test('a chmod that fails fails its test', () async {
    await expectLater(
      chmod('700', File(p.join(temp.path, 'missing'))),
      throwsA(isA<TestFailure>()),
    );
  });
}

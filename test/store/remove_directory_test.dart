import 'dart:io';

import 'package:muster/src/model/fetch_outcome.dart';
import 'package:muster/src/store/remove_directory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/chmod.dart';
import '../support/faults.dart';
import '../support/skipped_unless_modes_deny.dart';

void main() {
  late Directory temp;

  setUp(() async => temp = await .systemTemp.createTemp('muster-'));

  tearDown(() => temp.delete(recursive: true));

  test('a directory is removed with everything in it', () async {
    final Directory directory = .new(p.join(temp.path, 'gone'));
    await File(p.join(directory.path, 'a', 'b.txt')).create(recursive: true);
    await removeDirectory(directory.path);
    expect(await directory.exists(), isFalse);
  });

  test('nothing there is removed with nothing done', () async {
    await removeDirectory(p.join(temp.path, 'never', 'there'));
    expect(await temp.list().toList(), isEmpty);
  });

  test('a file there is removed', () async {
    final File file = await File(p.join(temp.path, 'file')).create();
    await removeDirectory(file.path);
    expect(await file.exists(), isFalse);
  });

  test('a link to nothing there is removed', () async {
    final Link link = await Link(p.join(temp.path, 'link'))
        .create(p.join(temp.path, 'nowhere'));
    await removeDirectory(link.path);
    expect(await link.exists(), isFalse);
  });

  test('a link there is removed, its target left', () async {
    final File target = await File(p.join(temp.path, 'target', 'kept.txt'))
        .create(recursive: true);
    final Link link = await Link(p.join(temp.path, 'link'))
        .create(p.dirname(target.path));
    await removeDirectory(link.path);
    expect(await link.exists(), isFalse);
    expect(await target.exists(), isTrue);
  });

  test('a directory that cannot be removed fails as StoreFailed, naming the '
      'path', () async {
    if (await skippedUnlessModesDeny(temp)) {
      return;
    }
    final Directory locked = await Directory(
      p.join(temp.path, 'gone', 'locked'),
    ).create(recursive: true);
    await File(p.join(locked.path, 'pinned')).create();
    await chmod('555', locked);
    try {
      await expectLater(
        removeDirectory(p.dirname(locked.path)),
        throwsA(
          storeFault(
            isA<StoreFailed>().having(
              (StoreFailed f) => f.path,
              'path',
              startsWith(p.dirname(locked.path)),
            ),
          ),
        ),
      );
    } finally {
      await chmod('755', locked);
    }
  });
}

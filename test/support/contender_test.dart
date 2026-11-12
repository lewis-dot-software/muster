import 'dart:io';

import 'package:test/test.dart';

import 'apart.dart';
import 'contender.dart';
import 'packages.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
  });

  tearDown(() => temp.delete(recursive: true));

  for (final Apart apart in Apart.values) {
    group('a contender run as ${apart.name}', () {
      late Contender holder;

      setUp(() async {
        holder = await .holding(apart, consumerIn(temp).path, 'app');
        await holder.told(.held);
        await holder.tell(.release);
      });

      test('that ends as told ends its end', () async {
        await holder.end();
      });

      for (final (String ending, Future<void> Function() end) in [
        ('end', () => holder.end()),
        ('kill', () => holder.kill()),
      ]) {
        test('that fails after the last word its test waits on fails its '
            '$ending', () async {
          // A hold hears its exit alone once it lets go, so it throws.
          await holder.tell(.go);
          await expectLater(
            holder.until((String said) => false),
            throwsA(isA<StateError>()),
          );
          await expectLater(end(), throwsA(isA<StateError>()));
        });
      }
    });
  }
}

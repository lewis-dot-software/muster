import 'dart:async';
import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/claim_path.dart';
import 'package:muster/src/store/claims.dart';
import 'package:test/test.dart';

import '../support/contenders.dart';
import '../support/faults.dart';
import '../support/packages.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('muster-');
  });

  tearDown(() => temp.delete(recursive: true));

  ClaimPath claimOf(String name) =>
      CheckoutPath.of(consumerIn(temp), .parse(name)!).claim;

  /// Claims whose every wait completes [waited], the first time.
  Claims waitingInto(Completer<void> waited) => .new(.posix, () async {
    if (!waited.isCompleted) {
      waited.complete();
    }
    await Future<void>.delayed(.zero);
  });

  /// Claims that fail the test where a claim is ever found held.
  Claims neverWaiting() =>
      .new(.posix, () async => fail('a claim no one holds was waited on'));

  test('a claim is held while its act runs, its file made with its '
      'directories where none is there, and the act given back', () async {
    final ClaimPath claim = claimOf('app');
    expect(
      await neverWaiting().holding(claim, () async {
        expect(await File(claim.path).exists(), isTrue);
        return 7;
      }),
      7,
    );
  });

  test('a claim held in the same isolate shuts out a second hold of it until '
      'the first lets go', () async {
    final ClaimPath claim = claimOf('app');
    final Completer<void> begun = .new();
    final Completer<void> go = .new();
    final Completer<void> waited = .new();
    final List<String> acts = [];
    final Future<void> first = Claims(.posix).holding(claim, () async {
      acts.add('first');
      begun.complete();
      await go.future;
      acts.add('first done');
    });
    await begun.future;
    final Future<void> second = waitingInto(waited)
        .holding(claim, () async => acts.add('second'));
    await waited.future;
    expect(acts, ['first']);
    go.complete();
    await Future.wait([first, second]);
    expect(acts, ['first', 'first done', 'second']);
  });

  test('claims on two checkouts are held at once', () async {
    final Completer<void> begun = .new();
    final Completer<void> go = .new();
    final Future<void> first = Claims(.posix).holding(claimOf('app'), () {
      begun.complete();
      return go.future;
    });
    await begun.future;
    await neverWaiting().holding(claimOf('bench'), () async {});
    go.complete();
    await first;
  });

  test('a claim is let go when its act throws, and the throw passes '
      'through', () async {
    final ClaimPath claim = claimOf('app');
    await expectLater(
      Claims(.posix).holding(claim, () async => throw const FormatException()),
      throwsA(isA<FormatException>()),
    );
    await neverWaiting().holding(claim, () async {});
  });

  test('a claim whose file cannot be made fails as StoreFailed', () async {
    await File(consumerIn(temp).path).create(recursive: true);
    await expectLater(
      Claims(.posix).holding(claimOf('app'), () async {}),
      throwsA(
        storeFault(
          isA<StoreFailed>().having(
            (StoreFailed f) => f.path,
            'path',
            startsWith(consumerIn(temp).path),
          ),
        ),
      ),
    );
  });

  for (final Apart apart in Apart.values) {
    group('a claim held by another ${apart.name}', () {
      late Contender holder;

      setUp(() async {
        holder = await Contender.holding(apart, consumerIn(temp).path, 'app');
        await holder.told(.held);
      });

      test('is waited on, and taken once it lets go', () async {
        final Completer<void> waited = .new();
        bool taken = false;
        final Future<void> hold = waitingInto(waited)
            .holding(claimOf('app'), () async => taken = true);
        await waited.future;
        expect(taken, isFalse);
        await holder.tell(.release);
        await hold;
        expect(taken, isTrue);
        await holder.end();
      });

      test('is waited on, and taken once its holder is killed', () async {
        final Completer<void> waited = .new();
        bool taken = false;
        final Future<void> hold = waitingInto(waited)
            .holding(claimOf('app'), () async => taken = true);
        await waited.future;
        expect(taken, isFalse);
        await holder.kill();
        await hold;
        expect(taken, isTrue);
      });
    });
  }

  test('a process started under a hold carries no claim past it', () async {
    late Process child;
    await Claims(.posix).holding(claimOf('app'), () async {
      child = await Process.start('sleep', ['600']);
    });
    final Contender other = await Contender.holding(
      .process,
      consumerIn(temp).path,
      'app',
    );
    await other.told(.held);
    await other.tell(.release);
    await other.end();
    child.kill();
    await child.exitCode;
  });
}

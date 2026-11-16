import 'dart:async';
import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/claim_path.dart';
import 'package:muster/src/store/claims.dart';
import 'package:muster/src/store/hold.dart';
import 'package:muster/src/store/libc.dart';
import 'package:muster/src/store/locker.dart';
import 'package:test/test.dart';

import '../support/act.dart';
import '../support/apart.dart';
import '../support/contender.dart';
import '../support/failing.dart';
import '../support/failing_libc.dart';
import '../support/faults.dart';
import '../support/keeping.dart';
import '../support/locker.dart';
import '../support/packages.dart';
import '../support/take.dart';
import '../support/waiting_into.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('muster-');
  });

  tearDown(() => temp.delete(recursive: true));

  ClaimPath claimOf(String name) =>
      CheckoutPath.of(consumerIn(temp), .parse(name)!).claim;

  /// Claims that fail the test where a claim is ever found held.
  Claims neverWaiting() =>
      .new(testLocker, () async => fail('a claim no one holds was waited on'));

  /// Whether the claim on the checkout [name], taken by [take] for an act
  /// that does [act], is let go, as a contender in a process of its own
  /// finds it, which starts no other, so no fork of another test file's
  /// carries the claim.
  Future<bool> letGoApart(String name, Take take, Act act) async {
    final Contender relet = await .reletting(
      consumerIn(temp).path,
      name,
      take,
      act,
    );
    final bool free = await relet.letGo();
    await relet.end();
    return free;
  }

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
    final Future<void> first = Claims(testLocker).holding(claim, () async {
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

  /// The locker whose C library's `open` fails as [open] fails and whose
  /// `flock` fails as [flock] fails, where each is given.
  FlockLocker failingLocker({Failing? open, Failing? flock}) => .new(
    FailingLibc((testLocker as FlockLocker).libc, open: open, flock: flock),
  );

  /// Claims whose hold's `flock` fails with [errno], its first [calls] alone
  /// where that is given and else every call, through a C library they are
  /// handed.
  Claims failingWith(int errno, [int? calls]) => .new(
    failingLocker(flock: .new(errno, calls)),
    () async => fail('a claim no one holds was waited on'),
  );

  /// Claims whose hold's `open` fails with [errno], its first [calls] alone
  /// where that is given and else every call, through a C library they are
  /// handed.
  Claims openFailingWith(int errno, [int? calls]) => .new(
    failingLocker(open: .new(errno, calls)),
    () async => fail('a claim no one holds was waited on'),
  );

  /// `EINVAL`, on every POSIX system, which `open` of a read alone never
  /// fails with for a path, so it reads as the VM's own.
  const int invalid = 22;

  test("a hold whose open of the claim's file fails, though the errno read "
      'after it names another failure, fails as a StoreFailed naming the '
      'file and the reason the open failed with', () async {
    final ClaimPath claim = claimOf('app');
    final Libc libc = (testLocker as FlockLocker).libc;
    const int noEntry = 2;
    await expectLater(
      Hold.take(claim, failingLocker(open: .new(invalid))),
      throwsA(
        storeFault(
          isA<StoreFailed>()
              .having((StoreFailed f) => f.path, 'path', claim.path)
              .having(
                (StoreFailed f) => f.reason,
                'reason',
                libc.message(noEntry),
              ),
        ),
      ),
    );
  });

  test("a hold whose open of the claim's file fails on its first try, though "
      'the file opens, takes the claim', () async {
    final ClaimPath claim = claimOf('app');
    expect(await openFailingWith(invalid, 1).holding(claim, () async => 7), 7);
    expect(await letGoApart('app', .once, .returns), isTrue);
  });

  test("a hold whose open of the claim's file fails every try, though the "
      "file opens, fails as a StoreFailed naming the file and the errno's "
      'reason', () async {
    final ClaimPath claim = claimOf('app');
    final Libc libc = (testLocker as FlockLocker).libc;
    await expectLater(
      openFailingWith(invalid).holding(claim, () async => fail('the act ran')),
      throwsA(
        storeFault(
          isA<StoreFailed>()
              .having((StoreFailed f) => f.path, 'path', claim.path)
              .having(
                (StoreFailed f) => f.reason,
                'reason',
                libc.message(invalid),
              ),
        ),
      ),
    );
    expect(await letGoApart('app', .once, .returns), isTrue);
  });

  test('a hold takes its lock through the C library its claims are given, '
      'so one whose flock finds the lock held finds the claim held, though '
      'no other hold has it', () async {
    final ClaimPath claim = claimOf('app');
    final Libc libc = (testLocker as FlockLocker).libc;
    await neverWaiting().holdingIfFree(claim, () async {});
    expect(
      await failingWith(libc.wouldBlock)
          .holdingIfFree(claim, () async => fail('the act ran')),
      isFalse,
    );
    expect(await letGoApart('app', .once, .returns), isTrue);
  });

  test("a hold whose C library's flock fails every try for any other reason "
      "fails as a StoreFailed naming the claim's file and the system's "
      'reason', () async {
    final ClaimPath claim = claimOf('app');
    final Libc libc = (testLocker as FlockLocker).libc;
    const int badDescriptor = 9;
    await expectLater(
      failingWith(badDescriptor)
          .holding(claim, () async => fail('the act ran')),
      throwsA(
        storeFault(
          isA<StoreFailed>()
              .having((StoreFailed f) => f.path, 'path', claim.path)
              .having(
                (StoreFailed f) => f.reason,
                'reason',
                libc.message(badDescriptor),
              ),
        ),
      ),
    );
    expect(await letGoApart('app', .once, .returns), isTrue);
  });

  test("a hold whose flock finds the lock held, though the errno read after "
      'its first try names another failure, finds the claim held', () async {
    final ClaimPath claim = claimOf('app');
    const int badDescriptor = 9;
    await Claims(testLocker).holding(claim, () async {
      expect(
        await failingWith(
          badDescriptor,
          1,
        ).holdingIfFree(claim, () async => fail('the act ran')),
        isFalse,
      );
    });
    expect(await letGoApart('app', .once, .returns), isTrue);
  });

  test("a hold of a claim no other hold has, though the errno read after its "
      "flock's first try names another failure, takes it", () async {
    final ClaimPath claim = claimOf('app');
    const int badDescriptor = 9;
    expect(
      await failingWith(badDescriptor, 1).holding(claim, () async => 7),
      7,
    );
    expect(await letGoApart('app', .once, .returns), isTrue);
  });

  test('claims on two checkouts are held at once', () async {
    final Completer<void> begun = .new();
    final Completer<void> go = .new();
    final Future<void> first = Claims(testLocker).holding(claimOf('app'), () {
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
      Claims(testLocker)
          .holding(claim, () async => throw const FormatException()),
      throwsA(isA<FormatException>()),
    );
    expect(await letGoApart('apart', .waiting, .throws), isTrue);
  });

  test('a claim whose file cannot be made fails as StoreFailed', () async {
    await File(consumerIn(temp).path).create(recursive: true);
    await expectLater(
      Claims(testLocker).holding(claimOf('app'), () async {}),
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

  test('a claim no hold has is taken at once where it is tried once, its '
      'file made, its act run and the claim let go after', () async {
    final ClaimPath claim = claimOf('app');
    bool ran = false;
    expect(
      await neverWaiting().holdingIfFree(claim, () async {
        expect(await File(claim.path).exists(), isTrue);
        ran = true;
      }),
      isTrue,
    );
    expect(ran, isTrue);
    expect(await letGoApart('apart', .once, .returns), isTrue);
  });

  test('a claim tried once is let go when its act throws, and the throw '
      'passes', () async {
    final ClaimPath claim = claimOf('app');
    await expectLater(
      neverWaiting().holdingIfFree(claim, () => throw StateError('act')),
      throwsStateError,
    );
    expect(await letGoApart('apart', .once, .throws), isTrue);
  });

  test(
    'a claim tried once whose file cannot be made fails as StoreFailed',
    () async {
      await File(consumerIn(temp).path).create(recursive: true);
      await expectLater(
        Claims(testLocker).holdingIfFree(claimOf('app'), () async {}),
        throwsA(storeFault(isA<StoreFailed>())),
      );
    },
  );

  for (final Apart apart in Apart.values) {
    group('a claim held by another ${apart.name}', () {
      late Contender holder;

      setUp(() async {
        holder = await .holding(apart, consumerIn(temp).path, 'app');
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

      test('is passed by where it is tried once, never waited on, and its '
          'act never run', () async {
        bool ran = false;
        expect(
          await neverWaiting().holdingIfFree(
            claimOf('app'),
            () async => ran = true,
          ),
          isFalse,
        );
        expect(ran, isFalse);
        await holder.tell(.release);
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
    final ClaimPath claim = claimOf('app');
    late Process child;
    await Claims(testLocker).holding(claim, () async {
      child = await .start('cat', const []);
    });
    addTearDown(() async {
      child.kill();
      await child.exitCode;
    });
    expect(await letGoApart('app', .once, .returns), isTrue);
  });

  final List<String> abandonedNames = [for (int i = 0; i < 10; i++) 'app$i'];

  /// Whether each claim on [abandonedNames], taken for an act that never
  /// ends and never released, is let go once its hold is collected, the
  /// claims that took it keeping what [keeping] names, as a contender in a
  /// process of its own finds it, which starts no other, so no fork of
  /// another test file's carries a claim.
  Future<List<bool>> collectedApart(Keeping keeping) async {
    final Contender abandoning = await .abandoning(
      consumerIn(temp).path,
      abandonedNames,
      keeping,
    );
    final List<bool> free = await abandoning.tried();
    await abandoning.end();
    return free;
  }

  test('a hold never released lets its claim go once it is collected, its '
      'claims and their locker collected with it', () async {
    expect(await collectedApart(.nothing), everyElement(isTrue));
  });

  test('a hold never released lets its claim go once it is collected, its '
      'claims still reachable', () async {
    expect(await collectedApart(.claims), everyElement(isTrue));
  });
}

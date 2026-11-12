import 'dart:async';
import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:test/test.dart';

import '../support/contenders.dart';
import '../support/git.dart';
import '../support/loads.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/spy_runner.dart';

void main() {
  late Directory temp;
  late Origin origin;
  late GitCodebase app;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('muster-');
    origin = await .make(temp, .new(hermetic(temp)));
    final Commit pin = await origin.commit(null, packageFiles('app'));
    await origin.ref('refs/heads/main', pin);
    app = codebaseOf(origin, pin);
    await writeManifest(atRoot(temp), [app]);
  });

  tearDown(() => temp.delete(recursive: true));

  test('two loads started together over one checkout both return Fetched at '
      'the same path, and the checkout is made once', () async {
    final List<SpyRunner> runners = [
      for (int i = 0; i < 2; i++) .new(hermetic(temp)),
    ];
    final List<Load> loads = await Future.wait([
      for (final SpyRunner runner in runners) loaderIn(temp, runner).load(),
    ]);
    for (final Load load in loads) {
      expect(load, loadedWith({'app': fetchedAt(checkoutAt(temp, 'app'))}));
    }
    final List<String> given = [
      for (final SpyRunner runner in runners) ...runner.given,
    ];
    expect(given.where((String c) => c.contains(' clone ')), hasLength(1));
    expect(
      given.where((String c) => c.contains(' worktree add ')),
      hasLength(1),
    );
    expect(given.where((String c) => c.contains(' get ')), hasLength(1));
  });

  for (final Apart apart in Apart.values) {
    test('a load waits on a checkout another ${apart.name} is making, then '
        'hands it out made once', () async {
      final Contender first = await Contender.loading(
        apart,
        root: consumerIn(temp).path,
        variables: loadEnvironment(temp).variables,
        manifests: [atRoot(temp)],
        pause: .resolve,
      );
      await first.told(.paused);
      final SpyRunner runner = .new(hermetic(temp));
      final Completer<void> waited = .new();
      final Future<Load> second = loaderIn(
        temp,
        runner,
        claims: .new(.posix, () async {
          if (!waited.isCompleted) {
            waited.complete();
          }
          await Future<void>.delayed(.zero);
        }),
      ).load();
      await waited.future;
      expect(runner.given, isEmpty);
      await first.tell(.go);
      expect(await first.done(), {
        'app': (outcome: 'Fetched', path: checkoutAt(temp, 'app')),
      });
      expect(
        await second,
        loadedWith({'app': fetchedAt(checkoutAt(temp, 'app'))}),
      );
      expect(
        runner.given,
        everyElement(anyOf(endsWith(' --version'), contains(' status '))),
      );
      await first.end();
    });
  }
}

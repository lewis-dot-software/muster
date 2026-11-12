import 'dart:async';
import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/contenders.dart';
import '../support/git.dart';
import '../support/loads.dart';
import '../support/locker.dart';
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
      final Contender first = await .loading(
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
        claims: .new(testLocker, () async {
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

  for (final Apart apart in Apart.values) {
    test('a load killed as its ${apart.name} makes the clone leaves a '
        'temporary clone the next load to make a clone removes', () async {
      final Contender killed = await .loading(
        apart,
        root: consumerIn(temp).path,
        variables: loadEnvironment(temp).variables,
        manifests: [atRoot(temp)],
        pause: .clone,
      );
      await killed.told(.paused);
      await killed.kill();
      final Directory left = .new(cloneOf(temp, app).temporary.path);
      expect(await left.exists(), isTrue);
      expect(
        await loaderIn(temp, .new(hermetic(temp))).load(),
        loadedWith({'app': fetchedAt(checkoutAt(temp, 'app'))}),
      );
      expect(await left.exists(), isFalse);
    });

    test('a temporary clone another ${apart.name} is making is left to it, '
        'and a load of another URL meanwhile never waits on it', () async {
      final Contender making = await .loading(
        apart,
        root: consumerIn(temp).path,
        variables: loadEnvironment(temp).variables,
        manifests: [atRoot(temp)],
        pause: .clone,
      );
      await making.told(.paused);
      final GitCodebase other = (
        name: .parse('other')!,
        url: .parse('${origin.url.url}/')!,
        commit: app.commit,
        root: app.root,
        toolchain: app.toolchain,
      );
      final String root = p.join(temp.path, 'elsewhere');
      final String manifest = p.join(root, 'muster.yaml');
      await writeManifest(manifest, [other]);
      expect(
        await loaderIn(
          temp,
          .new(hermetic(temp)),
          root: root,
          claims: .new(
            testLocker,
            () async => fail('a held claim was waited on'),
          ),
        ).load(named: [manifest]),
        loadedWith({
          'other': fetchedAt(p.join(root, '.dart_tool', 'muster', 'other')),
        }),
      );
      expect(
        await Directory(cloneOf(temp, app).temporary.path).exists(),
        isTrue,
      );
      await making.tell(.go);
      expect(await making.done(), {
        'app': (outcome: 'Fetched', path: checkoutAt(temp, 'app')),
      });
      expect(
        await Directory(cloneOf(temp, app).temporary.path).exists(),
        isFalse,
      );
      await making.end();
    });
  }
}

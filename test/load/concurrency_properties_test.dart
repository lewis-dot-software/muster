import 'dart:convert';
import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/cache_directory.dart';
import 'package:muster/src/model/clone_path.dart';
import 'package:muster/src/load/loader.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/model/hosted_codebase.dart';
import 'package:muster/src/model/lock_outcome.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/apart.dart';
import '../support/contender.dart';
import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/hosted.dart';
import '../support/loads.dart';
import '../support/manifests.dart';
import '../support/order_of.dart';
import '../support/origin.dart';
import '../support/outcome_case.dart';
import '../support/package_server.dart';
import '../support/packages.dart';
import '../support/pause.dart';
import '../support/said.dart';
import '../support/spy_runner.dart';
import '../support/write_file.dart';

/// The kind of the codebase a bench loads.
enum _Kind {
  /// A git codebase, its clone in the cache.
  git,

  /// A hosted package served on the loopback, resolved `alone` beside its
  /// example, with no clone.
  hosted;

  /// The commands a load of this kind holds a pause on, each met in every
  /// make of its checkout.
  List<Pause> get pauses => switch (this) {
    .git => const [.clone, .place, .resolve],
    .hosted => const [.unpack, .resolve],
  };

  /// Whether [command] makes a checkout of this kind: a worktree added or
  /// one checked out at its pin, or a package unpacked.
  bool makes(Command command) => switch (this) {
    .git => Pause.place.holds(command),
    .hosted => Pause.unpack.holds(command),
  };

  /// What the second of two loads may share with the first: a hosted
  /// codebase has no clone to share alone.
  List<_Shared> get shared => switch (this) {
    .git => _Shared.values,
    .hosted => const [.checkout],
  };
}

/// What the second of two loads shares with the first.
enum _Shared {
  /// One checkout, both loads having one root.
  checkout,

  /// One clone alone, each load having a root of its own.
  clone,
}

/// How the checkout stands before the first load.
enum _Before {
  /// Nothing is there, neither clone nor checkout.
  nothing,

  /// The checkout is made, then a file it was stamped with edited, a
  /// tracked file or the lock its package resolved on, so it stands no
  /// more and its stamp is still there.
  edited,
}

/// How a load ends before it is done.
enum _Ending {
  /// Killed, its isolate or its process, so it never lets its claims go
  /// itself.
  crash,

  /// Its paused command failed, its load given that failure, so it lets its
  /// claims go as the failure unwinds it.
  error,
}

/// A bench for one run: the codebase `app` of [kind], a git one at a commit
/// of an origin or a hosted one served on the loopback with its kept locks
/// written, a manifest at the consumer's root naming it, and the checkout as
/// [_Before] leaves it.
class _Bench {
  _Bench._(this.temp, this.kind, this.runner, this.manifest, this.server);

  static Future<_Bench> make(Directory temp, _Kind kind, _Before before) async {
    final PackageServer? server = switch (kind) {
      .git => null,
      .hosted => await .start(),
    };
    final SpyRunner runner = .new({
      ...hermetic(temp),
      if (server != null) ...pubVariables(temp, server),
    });
    final _Bench bench = ._(temp, kind, runner, atRoot(temp), server);
    switch (kind) {
      case .git:
        final Origin origin = await .make(temp, runner);
        final Commit pin = await origin.commit(null, packageFiles('app'));
        await origin.ref('refs/heads/main', pin);
        await writeManifest(bench.manifest, [codebaseOf(origin, pin)]);
      case .hosted:
        serveLeaf(server!, 'a', '1.0.0', example: true);
        await writeFile(
          bench.manifest,
          renderManifest([hostedEntryOf(_hostedApp)]),
        );
        expect(
          await bench.loader().lock(named: [bench.manifest]),
          isA<Locked>().having(
            (Locked l) => l.outcomes.values,
            'outcomes',
            everyElement(isA<LocksWritten>()),
          ),
        );
        final Directory checkouts = .new(
          p.join(bench.root, '.dart_tool', 'muster'),
        );
        if (await checkouts.exists()) {
          await checkouts.delete(recursive: true);
        }
    }
    switch (before) {
      case .nothing:
        break;
      case .edited:
        expect(await bench.load(), loadedWith({'app': isA<Fetched>()}));
        final String edited = switch (kind) {
          .git => p.join(bench.checkoutUnder(bench.root), 'pubspec.yaml'),
          .hosted => p.join(bench.packageUnder(bench.root), 'pubspec.lock'),
        };
        await File(edited).writeAsString('# edited\n', mode: .append);
    }
    return bench;
  }

  final Directory temp;
  final _Kind kind;
  final SpyRunner runner;
  final String manifest;

  /// The server a hosted codebase is fetched from, null for a git one.
  final PackageServer? server;

  String get root => consumerIn(temp).path;

  /// The root of a consumer of its own.
  String get otherRoot => p.join(temp.path, 'other');

  /// The variables a load reads, pub sent to [server] where there is one.
  Map<String, String> get variables => loadEnvironment(temp, {
    if (server case final PackageServer server) ...pubVariables(temp, server),
  }).variables;

  /// A loader in this isolate, its checkouts under [root].
  Loader loader([String? root]) => loaderIn(
    temp,
    runner,
    root: root,
    variables: {
      if (server case final PackageServer server) ...pubVariables(temp, server),
    },
  );

  /// A load in this isolate of the manifest, its checkouts under [root].
  Future<Load> load([String? root]) => loader(root).load(named: [manifest]);

  /// A contender [apart] loading the manifest, its checkouts under [root],
  /// holding the command [pause] names where one is given.
  Future<Contender> contender(Apart apart, String root, {Pause? pause}) =>
      Contender.loading(
        apart,
        root: root,
        variables: variables,
        manifests: [manifest],
        pause: pause,
      );

  /// The checkout of `app` under [root].
  String checkoutUnder(String root) =>
      p.join(root, '.dart_tool', 'muster', 'app');

  /// The package the checkout of `app` under [root] hands out.
  String packageUnder(String root) => switch (kind) {
    .git => checkoutUnder(root),
    .hosted => p.join(checkoutUnder(root), 'a-1.0.0'),
  };

  /// The stamp of the checkout of `app` under [root].
  File stampUnder(String root) => .new('${checkoutUnder(root)}.stamp');

  Future<void> close() async => server?.close();
}

/// The hosted codebase `app`, the package `a` at `1.0.0` resolved `alone`.
final HostedCodebase _hostedApp = hostedOf('a');

/// [body] run on a bench of [kind] of its own in a directory of its own, the
/// checkout first as [before] leaves it.
Future<void> _onBench(
  _Kind kind,
  _Before before,
  Future<void> Function(_Bench bench) body,
) => inTemp((Directory temp) async {
  final _Bench bench = await .make(temp, kind, before);
  try {
    await body(bench);
  } finally {
    await bench.close();
  }
});

/// Whether [command] reaches a URL, by a clone or a fetch.
bool _reachesUrl(Command command) => switch (command.executable) {
  .git =>
    command.arguments.contains('clone') || command.arguments.contains('fetch'),
  .dart || .flutter => false,
};

void main() {
  property("STO-1: Two loads at once, as isolates of one process or as "
      "separate processes, never act on one clone or checkout together, "
      "git or hosted, and the second: waits, uses the first's clone with "
      "no clone or fetch of its own, hands out the first's checkout "
      "untouched where they share one.", (Draw draw) async {
    for (final _Kind kind in _Kind.values) {
      for (final Apart firstApart in Apart.values) {
        for (final Apart secondApart in Apart.values) {
          for (final Pause pause in kind.pauses) {
            for (final _Shared shared in kind.shared) {
              for (final _Before before in _Before.values) {
                await _contend(
                  kind,
                  firstApart,
                  secondApart,
                  pause,
                  shared,
                  before,
                );
              }
            }
          }
        }
      }
    }
  }, settings: .new(runs: 1));

  property('STO-7: Of a claim held by a load that crashed, which never '
      'released it, or that failed, which released it as the failure '
      'unwound: it never blocks a later load, that load hands out the '
      'checkout made whole, that load leaves no temporary clone.', (
    Draw draw,
  ) async {
    for (final Apart apart in Apart.values) {
      for (final Pause pause in _Kind.git.pauses) {
        for (final _Ending ending in _Ending.values) {
          for (final _Before before in _Before.values) {
            await _endThenLoad(apart, pause, ending, before);
          }
        }
      }
    }
  }, settings: .new(runs: 1));

  property('STO-27: Two loads at once over several codebases, git and hosted, '
      'sharing a root or a clone alone, each in an order of its own, never '
      'wait on each other, and each gives every codebase `Fetched`.', (
    Draw draw,
  ) async {
    final int count = draw(
      .integer(min: 2, max: _Several.values.length),
      label: 'count',
    );
    final List<_Several> firstOrder = draw(
      orderOf(_Several.values),
      label: 'first order',
    ).take(count).toList();
    final List<_Several> secondOrder = draw(
      orderOf(firstOrder),
      label: 'second order',
    );
    final List<_Several> drawn = firstOrder;
    final Pause pause = draw(
      .element([
        for (final Pause pause in Pause.values)
          if (drawn.any((_Several c) => c.kind.pauses.contains(pause))) pause,
      ]),
      label: 'pause',
    );
    final _Shared shared = draw(.element(_Shared.values), label: 'shared');
    final Apart firstApart = draw(.element(Apart.values), label: 'first');
    final Apart secondApart = draw(.element(Apart.values), label: 'second');
    await _severalAtOnce(
      firstOrder,
      secondOrder,
      pause,
      shared,
      firstApart,
      secondApart,
    );
  }, settings: .new(runs: 12, shrinkSteps: gitShrinks));

  property('STO-29: A make cut short or failed, git or hosted, leaves no '
      'stamp once it has touched the checkout, even one an earlier make '
      'wrote, and the stamp as it stood before then, so the next load makes '
      'the checkout again.', (Draw draw) async {
    for (final _Kind kind in _Kind.values) {
      for (final Pause pause in kind.pauses) {
        for (final _Ending ending in _Ending.values) {
          for (final _Before before in _Before.values) {
            await _endUnstamped(kind, pause, ending, before);
          }
        }
      }
    }
  }, settings: .new(runs: 1));
}

/// Two loads of one manifest, the first [firstApart] held at the command
/// [pause] names, the second [secondApart] sharing what [shared] names with
/// it, the checkout first as [before] leaves it.
Future<void> _contend(
  _Kind kind,
  Apart firstApart,
  Apart secondApart,
  Pause pause,
  _Shared shared,
  _Before before,
) => _onBench(kind, before, (_Bench bench) async {
  final String at =
      'kind ${kind.name}, first ${firstApart.name}, '
      'second ${secondApart.name}, pause ${pause.name}, '
      'shared ${shared.name}, before ${before.name}';
  final String secondRoot = switch (shared) {
    .checkout => bench.root,
    .clone => bench.otherRoot,
  };
  // What the second load must not run while the first is paused: on one
  // checkout, any command at all, since its claim comes before the survey,
  // and on one clone, any command on the clone.
  bool acts(Command command) => switch (shared) {
    .checkout => true,
    .clone => Pause.clone.holds(command),
  };
  final Contender first = await bench.contender(
    firstApart,
    bench.root,
    pause: pause,
  );
  await first.told(.paused);
  final Contender second = await bench.contender(secondApart, secondRoot);
  final String met = await second.until(
    (String said) =>
        said == Said.waiting.name ||
        said.startsWith('${Said.done.name} ') ||
        second.ran.any(acts),
  );
  expect(met, Said.waiting.name, reason: at);
  expect(second.ran.where(acts), isEmpty, reason: at);
  await first.tell(.go);
  expect(await first.done(), {
    'app': (outcome: OutcomeCase.fetched, path: bench.packageUnder(bench.root)),
  }, reason: at);
  expect(await second.done(), {
    'app': (outcome: OutcomeCase.fetched, path: bench.packageUnder(secondRoot)),
  }, reason: at);
  expect(second.ran.where(_reachesUrl), isEmpty, reason: at);
  switch (shared) {
    case .checkout:
      expect(
        second.ran,
        everyElement(
          predicate(
            (Command c) =>
                c.arguments.last == '--version' ||
                c.arguments.contains('status'),
            'the survey alone',
          ),
        ),
        reason: at,
      );
      expect(first.ran.where(kind.makes), hasLength(1), reason: at);
    case .clone:
      expect(first.ran.where(kind.makes), hasLength(1), reason: at);
      expect(second.ran.where(kind.makes), hasLength(1), reason: at);
  }
  await first.end();
  await second.end();
});

/// A load [apart] held at the command [pause] names, then ended as [ending]
/// says, the checkout first as [before] leaves it, and a later load of the
/// same manifest in this isolate.
Future<void> _endThenLoad(
  Apart apart,
  Pause pause,
  _Ending ending,
  _Before before,
) => _onBench(.git, before, (_Bench bench) async {
  final String at =
      'apart ${apart.name}, pause ${pause.name}, ending ${ending.name}, '
      'before ${before.name}';
  final Contender ended = await _ended(bench, apart, pause, ending, at);
  final Directory temp = bench.temp;
  final String checkout = bench.checkoutUnder(bench.root);
  expect(
    await bench.load(),
    loadedWith({'app': fetchedAt(checkout)}),
    reason: at,
  );
  expect(
    await File(p.join(checkout, 'pubspec.yaml')).readAsString(),
    pubspecOf('app'),
    reason: at,
  );
  expect(
    jsonDecode(
      await File(p.join(checkout, '.dart_tool', 'package_config.json'))
          .readAsString(),
    ),
    isA<Map<String, Object?>>(),
    reason: at,
  );
  final CacheDirectory cache = cacheDirectoryIn(temp);
  expect(
    [
      await for (final FileSystemEntity entity in Directory(cache.path).list())
        if (ClonePath.ofTemporary(cache, p.basename(entity.path)) != null)
          entity.path,
    ],
    isEmpty,
    reason: at,
  );
  switch (ending) {
    case .crash:
      break;
    case .error:
      await ended.end();
  }
});

/// A contender [apart] loading [bench]'s manifest, held at the command
/// [pause] names, then ended as [ending] says, the case [at] named in each
/// failure.
Future<Contender> _ended(
  _Bench bench,
  Apart apart,
  Pause pause,
  _Ending ending,
  String at,
) async {
  final Contender ended = await bench.contender(
    apart,
    bench.root,
    pause: pause,
  );
  await ended.told(.paused);
  switch (ending) {
    case .crash:
      await ended.kill();
    case .error:
      await ended.tell(.fail);
      expect(
        (await ended.done())['app']?.outcome,
        OutcomeCase.commandFailed,
        reason: at,
      );
  }
  return ended;
}

/// A load of [kind] in a process of its own held at the command [pause]
/// names, then ended as [ending] says, the checkout first as [before] leaves
/// it, and a later load of the same manifest in this isolate.
Future<void> _endUnstamped(
  _Kind kind,
  Pause pause,
  _Ending ending,
  _Before before,
) => _onBench(kind, before, (_Bench bench) async {
  final String at =
      'kind ${kind.name}, pause ${pause.name}, ending ${ending.name}, '
      'before ${before.name}';
  final File stamp = bench.stampUnder(bench.root);
  final String? stood = await stamp.exists()
      ? await stamp.readAsString()
      : null;
  final Contender ended = await _ended(bench, .process, pause, ending, at);
  final String? left = await stamp.exists() ? await stamp.readAsString() : null;
  switch (pause) {
    case .clone:
      // Held on the clone, before the make touches the checkout.
      expect(left, stood, reason: at);
    case .place || .unpack || .resolve:
      expect(left, isNull, reason: at);
  }
  bench.runner.commands.clear();
  expect(
    await bench.load(),
    loadedWith({'app': fetchedAt(bench.packageUnder(bench.root))}),
    reason: at,
  );
  expect(bench.runner.commands.where(kind.makes), hasLength(1), reason: at);
  switch (ending) {
    case .crash:
      break;
    case .error:
      await ended.end();
  }
});

/// A codebase a load over several may name.
enum _Several {
  /// A git codebase on the first origin.
  x,

  /// A git codebase on the first origin at another commit, so it shares
  /// `x`'s clone.
  y,

  /// A git codebase on an origin of its own.
  z,

  /// A hosted codebase.
  h;

  /// The kind of this codebase.
  _Kind get kind => switch (this) {
    .x || .y || .z => .git,
    .h => .hosted,
  };
}

/// Two loads at once of the codebases [firstOrder] names, each from a
/// manifest of its own in its own order, the second's [secondOrder], the
/// first [firstApart] held at the command [pause] names until the second
/// waits or is done, the second [secondApart] sharing what [shared] names
/// with it.
Future<void> _severalAtOnce(
  List<_Several> firstOrder,
  List<_Several> secondOrder,
  Pause pause,
  _Shared shared,
  Apart firstApart,
  Apart secondApart,
) => inTemp((Directory temp) async {
  final PackageServer server = await .start();
  try {
    final Map<String, String> pub = pubVariables(temp, server);
    final SpyRunner runner = .new({...hermetic(temp), ...pub});
    final Origin first = await .make(temp, runner);
    final Origin second = await .make(
      await .new(p.join(temp.path, 'z')).create(),
      runner,
    );
    final Map<_Several, Entry> entries = {};
    for (final _Several codebase in _Several.values) {
      final String name = codebase.name;
      switch (codebase) {
        case .x || .y || .z:
          final Origin origin = codebase == .z ? second : first;
          final Commit pin = await origin.commit(null, packageFiles(name));
          await origin.ref('refs/heads/$name', pin);
          entries[codebase] = entryOf(codebaseOf(origin, pin, name: name));
        case .h:
          serveLeaf(server, 'a', '1.0.0', example: true);
          entries[codebase] = hostedEntryOf(hostedOf('a', name: name));
      }
    }
    final String firstRoot = consumerIn(temp).path;
    final String secondRoot = switch (shared) {
      .checkout => firstRoot,
      .clone => p.join(temp.path, 'other'),
    };
    final Map<String, String> variables = loadEnvironment(temp, pub).variables;
    final List<String> manifests = [];
    for (final (int i, List<_Several> order) in [
      firstOrder,
      secondOrder,
    ].indexed) {
      final String manifest = p.join(temp.path, 'manifests', 'm$i.yaml');
      await writeFile(
        manifest,
        renderManifest([
          for (final _Several codebase in order) entries[codebase]!,
        ]),
      );
      // Every hosted codebase loads on a kept lock, which a lock writes,
      // and the checkouts it leaves are removed, so the loads find none.
      expect(
        await loaderIn(temp, runner, variables: pub).lock(named: [manifest]),
        isA<Locked>(),
      );
      manifests.add(manifest);
    }
    final Directory checkouts = .new(p.join(firstRoot, '.dart_tool', 'muster'));
    if (await checkouts.exists()) {
      await checkouts.delete(recursive: true);
    }
    final Contender firstLoad = await .loading(
      firstApart,
      root: firstRoot,
      variables: variables,
      manifests: [manifests.first],
      pause: pause,
    );
    await firstLoad.told(.paused);
    final Contender secondLoad = await .loading(
      secondApart,
      root: secondRoot,
      variables: variables,
      manifests: [manifests.last],
    );
    await secondLoad.until(
      (String said) =>
          said == Said.waiting.name || said.startsWith('${Said.done.name} '),
    );
    await firstLoad.tell(.go);
    for (final (Contender load, String root, List<_Several> order) in [
      (firstLoad, firstRoot, firstOrder),
      (secondLoad, secondRoot, secondOrder),
    ]) {
      expect(await load.done(), {
        for (final _Several codebase in order)
          codebase.name: (
            outcome: OutcomeCase.fetched,
            path: switch (codebase.kind) {
              .git => p.join(root, '.dart_tool', 'muster', codebase.name),
              .hosted => p.join(
                root,
                '.dart_tool',
                'muster',
                codebase.name,
                'a-1.0.0',
              ),
            },
          ),
      });
    }
    await firstLoad.end();
    await secondLoad.end();
  } finally {
    await server.close();
  }
});

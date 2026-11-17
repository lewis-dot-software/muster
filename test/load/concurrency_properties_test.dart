import 'dart:convert';
import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/apart.dart';
import '../support/contender.dart';
import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/loads.dart';
import '../support/origin.dart';
import '../support/outcome_case.dart';
import '../support/packages.dart';
import '../support/pause.dart';
import '../support/said.dart';
import '../support/spy_runner.dart';

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

  /// The checkout is made, then a tracked file edited, so it stands no more.
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

/// A bench for one run: an origin with the codebase `app` at a commit, a
/// manifest at the consumer's root naming it, and the checkout as [_Before]
/// leaves it.
class _Bench {
  _Bench._(this.temp, this.runner, this.manifest);

  static Future<_Bench> make(Directory temp, _Before before) async {
    final SpyRunner runner = .new(hermetic(temp));
    final Origin origin = await .make(temp, runner);
    final Commit pin = await origin.commit(null, packageFiles('app'));
    await origin.ref('refs/heads/main', pin);
    final GitCodebase app = codebaseOf(origin, pin);
    await writeManifest(atRoot(temp), [app]);
    final _Bench bench = ._(temp, runner, atRoot(temp));
    switch (before) {
      case .nothing:
        break;
      case .edited:
        expect(await bench.load(), loadedWith({'app': isA<Fetched>()}));
        await File(p.join(checkoutAt(temp, 'app'), 'pubspec.yaml'))
            .writeAsString('# edited\n', mode: .append);
    }
    return bench;
  }

  final Directory temp;
  final SpyRunner runner;
  final String manifest;

  String get root => consumerIn(temp).path;

  /// The root of a consumer of its own.
  String get otherRoot => p.join(temp.path, 'other');

  Map<String, String> get variables => loadEnvironment(temp).variables;

  /// A load in this isolate of the manifest, its checkouts under [root].
  Future<Load> load([String? root]) =>
      loaderIn(temp, runner, root: root).load(named: [manifest]);

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
}

/// Whether [command] makes a checkout: a worktree added, or one checked out
/// at its pin.
bool _makes(Command command) => Pause.place.holds(command);

void main() {
  property(
    'Two loads at once, as isolates of one process or as separate processes, '
    'never act on one clone or checkout together, and the second hands out '
    "the first's checkout untouched.",
    (Draw draw) async {
      final Apart firstApart = draw(
        .element(Apart.values),
        label: 'firstApart',
      );
      final Apart secondApart = draw(
        .element(Apart.values),
        label: 'secondApart',
      );
      final Pause pause = draw(.element(Pause.values), label: 'pause');
      final _Shared shared = draw(.element(_Shared.values), label: 'shared');
      final _Before before = draw(.element(_Before.values), label: 'before');
      await inTemp((Directory temp) async {
        final _Bench bench = await .make(temp, before);
        final String secondRoot = switch (shared) {
          .checkout => bench.root,
          .clone => bench.otherRoot,
        };
        // What the second load must not run while the first is paused: on one
        // checkout, any command at all, since its claim comes before the
        // survey, and on one clone, any command on the clone.
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
        expect(met, Said.waiting.name);
        expect(second.ran.where(acts), isEmpty);
        await first.tell(.go);
        expect(await first.done(), {
          'app': (
            outcome: OutcomeCase.fetched,
            path: bench.checkoutUnder(bench.root),
          ),
        });
        expect(await second.done(), {
          'app': (
            outcome: OutcomeCase.fetched,
            path: bench.checkoutUnder(secondRoot),
          ),
        });
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
            );
            expect(first.ran.where(_makes), hasLength(1));
          case .clone:
            expect(first.ran.where(_makes), hasLength(1));
            expect(second.ran.where(_makes), hasLength(1));
        }
        await first.end();
        await second.end();
      });
    },
    settings: .new(runs: 12, shrinkSteps: gitShrinks),
  );

  property(
    'A claim held by a load that crashed, which never released it, or that '
    'failed, which released it as the failure unwound, never blocks a later '
    'load.',
    (Draw draw) async {
      final Apart apart = draw(.element(Apart.values), label: 'apart');
      final Pause pause = draw(.element(Pause.values), label: 'pause');
      final _Ending ending = draw(.element(_Ending.values), label: 'ending');
      final _Before before = draw(.element(_Before.values), label: 'before');
      await inTemp((Directory temp) async {
        final _Bench bench = await .make(temp, before);
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
            );
        }
        final String checkout = bench.checkoutUnder(bench.root);
        expect(await bench.load(), loadedWith({'app': fetchedAt(checkout)}));
        expect(
          await File(p.join(checkout, 'pubspec.yaml')).readAsString(),
          pubspecOf('app'),
        );
        expect(
          jsonDecode(
            await File(p.join(checkout, '.dart_tool', 'package_config.json'))
                .readAsString(),
          ),
          isA<Map<String, Object?>>(),
        );
        switch (ending) {
          case .crash:
            break;
          case .error:
            await ended.end();
        }
      });
    },
    settings: .new(runs: 12, shrinkSteps: gitShrinks),
  );
}

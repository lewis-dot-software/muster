import 'dart:convert';
import 'dart:io';

import 'package:glados/glados.dart';
import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:path/path.dart' as p;

import '../support/apart.dart';
import '../support/contender.dart';
import '../support/outcome_case.dart';
import '../support/pause.dart';
import '../support/git.dart';
import '../support/loads.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/said.dart';
import '../support/shrinking_at_most.dart';
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

/// How a load ends without letting its claims go itself.
enum _Ending {
  /// Killed, its isolate or its process.
  crash,

  /// Its paused command failed, its load given that failure.
  error,
}

/// A bench for one draw: an origin with the codebase `app` at a commit, a
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
  Glados(
    any
        .combine5(
          any.choose(Apart.values),
          any.choose(Apart.values),
          any.choose(Pause.values),
          any.choose(_Shared.values),
          any.choose(_Before.values),
          (
            Apart first,
            Apart second,
            Pause pause,
            _Shared shared,
            _Before before,
          ) => (
            first: first,
            second: second,
            pause: pause,
            shared: shared,
            before: before,
          ),
        )
        .shrinkingAtMost(gitTries),
    .new(numRuns: 12),
  ).test(
    'Two loads at once, as isolates of one process or as separate processes, '
    'never act on one clone or checkout together, and the second hands out '
    "the first's checkout untouched.",
    (
      ({Apart first, Apart second, Pause pause, _Shared shared, _Before before})
      draw,
    ) => inTemp((Directory temp) async {
      final _Bench bench = await _Bench.make(temp, draw.before);
      final String secondRoot = switch (draw.shared) {
        .checkout => bench.root,
        .clone => bench.otherRoot,
      };
      // What the second load must not run while the first is paused: on one
      // checkout, any command at all, since its claim comes before the
      // survey, and on one clone, any command on the clone.
      bool acts(Command command) => switch (draw.shared) {
        .checkout => true,
        .clone => Pause.clone.holds(command),
      };
      final Contender first = await bench.contender(
        draw.first,
        bench.root,
        pause: draw.pause,
      );
      await first.told(.paused);
      final Contender second = await bench.contender(draw.second, secondRoot);
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
      switch (draw.shared) {
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
    }),
  );

  Glados(
    any
        .combine4(
          any.choose(Apart.values),
          any.choose(Pause.values),
          any.choose(_Ending.values),
          any.choose(_Before.values),
          (Apart apart, Pause pause, _Ending ending, _Before before) =>
              (apart: apart, pause: pause, ending: ending, before: before),
        )
        .shrinkingAtMost(gitTries),
    .new(numRuns: 12),
  ).test(
    'A claim left by a load that ended without releasing it, whether by a '
    'crash or by an error, never blocks a later load.',
    (({Apart apart, Pause pause, _Ending ending, _Before before}) draw) =>
        inTemp((Directory temp) async {
          final _Bench bench = await _Bench.make(temp, draw.before);
          final Contender ended = await bench.contender(
            draw.apart,
            bench.root,
            pause: draw.pause,
          );
          await ended.told(.paused);
          switch (draw.ending) {
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
          switch (draw.ending) {
            case .crash:
              break;
            case .error:
              await ended.end();
          }
        }),
  );
}

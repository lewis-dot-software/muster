import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/codebase.dart';
import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/store/checkouts.dart';
import 'package:test/test.dart';

import '../support/files_under.dart';
import '../support/git.dart';
import '../support/git_shrinks.dart';
import '../support/loads.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/spy_runner.dart';
import '../support/write_file.dart';

/// The files a pin may hold beside its package's, each drawn or not.
const List<String> _pool = [
  'lib/a.dart',
  'lib/b/c.dart',
  'README.md',
  'tool/run.sh',
];

/// What the pin's `.gitignore` ignores: `.dart_tool/`, `ignored/` and every
/// `.log`.
const String _gitignore = '.dart_tool/\nignored/\n*.log\n';

/// One act on a checkout between two loads.
enum _Act {
  /// A tracked file's contents rewritten.
  editTracked,

  /// A tracked file deleted.
  deleteTracked,

  /// An untracked file written.
  addUntracked,

  /// A file the `.gitignore` ignores written.
  addIgnored,

  /// A file written in the root's `.dart_tool/`.
  addInDartTool,

  /// `HEAD` moved off the pin by a commit made in the checkout.
  moveHead,

  /// The stamp deleted.
  deleteStamp,
}

/// The acts that leave a checkout that no longer stands.
const Set<_Act> _forcing = {
  .editTracked,
  .deleteTracked,
  .moveHead,
  .deleteStamp,
};

/// What stands in a checkout's place once the acts on it are done.
enum _Place {
  /// The checkout as the acts left it.
  checkout,

  /// Its directory deleted.
  gone,

  /// A directory that is no worktree, holding a file.
  directory,

  /// A file.
  file,
}

/// What a tool writes beside a checkout's tracked files.
enum _Kind { untracked, untrackedInTracked, ignored, inDartTool }

/// A file a tool writes: its `kind`, the index `at` that names it, and its
/// `contents`.
typedef _Write = (_Kind kind, int at, String contents);

/// An act on a checkout: the `act`, and the index `at` of the file it
/// acts on.
typedef _Step = (_Act act, int at);

/// The path, from the checkout's top in `/` separators, of the file of
/// [kind] that [at] names.
String _written(_Kind kind, int at) => switch (kind) {
  .untracked => 'stray/$at.txt',
  .untrackedInTracked => 'lib/tool$at.dart',
  .ignored => at.isEven ? 'ignored/$at.txt' : 'out$at.log',
  .inDartTool => '.dart_tool/tool$at',
};

/// The files of a pin holding the package `app`, the `.gitignore` and the
/// files of [_pool] at [pool], their contents set by [seed].
Map<String, String> _pinFiles(Set<int> pool, int seed) => {
  ...packageFiles('app'),
  '.gitignore': _gitignore,
  for (final int i in pool) _pool[i]: 'file $i of $seed\n',
};

/// A bench for one run: an origin, its checkouts, and what a test reads of
/// them.
class _Bench {
  _Bench._(this.temp, this.runner, this.origin, this.checkouts, this.locks);

  static Future<_Bench> make(Directory temp) async {
    final SpyRunner runner = .new(hermetic(temp));
    return ._(
      temp,
      runner,
      await .make(temp, runner),
      checkoutsIn(temp, runner),
      locksBeside(atRoot(temp)),
    );
  }

  final Directory temp;
  final SpyRunner runner;
  final Origin origin;
  final Checkouts checkouts;
  final LocksDirectory locks;

  CheckoutPath get checkout => appCheckout(checkouts);

  String inCheckout(String file) => fileIn(checkout, file);

  Future<void> write(String file, String contents) =>
      writeFile(inCheckout(file), contents);
}

void main() {
  property(
    "STO-4: A checkout made again holds exactly the pin's tracked files, "
    'whatever stood in its place: every edit is reverted and every file the '
    'pin lacks is removed.',
    (Draw draw) async {
      final Set<int> pool = draw(
        .set(.integer(min: 0, max: _pool.length - 1)),
        label: 'pool',
      );
      final int seed = draw(.integer(min: 0, max: 999), label: 'seed');
      final _Act forcing = draw(.element(_forcing.toList()), label: 'forcing');
      final bool elsewhere = draw(.boolean(), label: 'elsewhere');
      final List<_Step> acts = draw(
        .list(
          .build(
            (Draw draw) =>
                (draw(.element(_Act.values)), draw(.integer(min: 0, max: 19))),
          ),
          maxLength: 3,
        ),
        label: 'acts',
      );
      final _Place place = draw(.element(_Place.values), label: 'place');
      await inTemp((Directory temp) async {
        final _Bench bench = await .make(temp);
        final Map<String, String> files = _pinFiles(pool, seed);
        final Commit pin = await bench.origin.commit(null, files);
        await bench.origin.ref('refs/heads/main', pin);
        final Commit other = await bench.origin.commit(null, {
          ...packageFiles('app'),
          'lib/elsewhere.dart': 'elsewhere\n',
        });
        await bench.origin.ref('refs/heads/side', other);
        final GitCodebase codebase = codebaseOf(bench.origin, pin);
        if (elsewhere) {
          await bench.checkouts.checkout(
            Git(codebaseOf(bench.origin, other)),
            bench.locks,
          );
        }
        await bench.checkouts.checkout(Git(codebase), bench.locks);
        final List<String> tracked = files.keys.toList();
        for (final (_Act act, int at) in [(forcing, 0), ...acts]) {
          final String file = tracked[at % tracked.length];
          switch (act) {
            case .editTracked:
              await bench.write(file, 'edited $at\n');
            case .deleteTracked:
              if (await File(bench.inCheckout(file)).exists()) {
                await File(bench.inCheckout(file)).delete();
              }
            case .addUntracked:
              await bench.write(_written(.untracked, at), 'untracked');
            case .addIgnored:
              await bench.write(_written(.ignored, at), 'ignored');
            case .addInDartTool:
              await bench.write(_written(.inDartTool, at), 'tool');
            case .moveHead:
              await bench.runner.run((
                executable: .git,
                arguments: [
                  '-C',
                  bench.checkout.path,
                  'commit',
                  '--quiet',
                  '--allow-empty',
                  '--message=off $at',
                ],
              ));
            case .deleteStamp:
              if (await File(bench.checkout.stamp.path).exists()) {
                await File(bench.checkout.stamp.path).delete();
              }
          }
        }
        switch (place) {
          case .checkout:
            break;
          case .gone:
            await Directory(bench.checkout.path).delete(recursive: true);
          case .directory:
            await Directory(bench.checkout.path).delete(recursive: true);
            await bench.write('stray.txt', 'no worktree');
          case .file:
            await Directory(bench.checkout.path).delete(recursive: true);
            await File(bench.checkout.path).writeAsString('no directory');
        }
        await bench.checkouts.checkout(Git(codebase), bench.locks);
        expect(
          await filesUnder(bench.checkout.path, less: ['.git', '.dart_tool']),
          files,
        );
        for (int at = 0; at < 20; at++) {
          expect(
            await File(bench.inCheckout(_written(.inDartTool, at))).exists(),
            isFalse,
          );
        }
      });
    },
    settings: .new(runs: 15, shrinkSteps: gitShrinks),
  );

  property(
    'STO-8: A standing checkout keeps everything a tool wrote beside its '
    'tracked files, ignored or untracked, and is handed out with nothing run '
    'but its survey.',
    (Draw draw) async {
      final List<_Write> writes = draw(
        .list(
          .build(
            (Draw draw) => (
              draw(.element(_Kind.values)),
              draw(.integer(min: 0, max: 9)),
              draw(.string(alphabet: .lettersAndDigits)),
            ),
          ),
          minLength: 1,
        ),
        label: 'writes',
      );
      await inTemp((Directory temp) async {
        final _Bench bench = await .make(temp);
        final Commit pin = await bench.origin.commit(null, _pinFiles({0}, 0));
        await bench.origin.ref('refs/heads/main', pin);
        final GitCodebase codebase = codebaseOf(bench.origin, pin);
        await bench.checkouts.checkout(Git(codebase), bench.locks);
        final Map<String, String> wrote = {
          for (final (_Kind kind, int at, String contents) in writes)
            _written(kind, at): contents,
        };
        for (final MapEntry<String, String>(:key, :value) in wrote.entries) {
          await bench.write(key, value);
        }
        bench.runner.commands.clear();
        // A new load's, since a load reads each SDK version once.
        await checkoutsIn(
          temp,
          bench.runner,
        ).checkout(Git(codebase), bench.locks);
        expect(bench.runner.given, hasLength(2));
        expect(bench.runner.given.last, contains(' status '));
        for (final MapEntry<String, String>(:key, :value) in wrote.entries) {
          expect(await File(bench.inCheckout(key)).readAsString(), value);
        }
      });
    },
    settings: .new(runs: 15, shrinkSteps: gitShrinks),
  );
}

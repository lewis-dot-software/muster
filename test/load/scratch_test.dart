import 'dart:async';
import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/store/claims.dart';
import 'package:muster/src/store/runner.dart';
import 'package:muster/src/store/store_fault.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/chmod.dart';
import '../support/files_under.dart';
import '../support/git.dart';
import '../support/loads.dart';
import '../support/locker.dart';
import '../support/origin.dart';
import '../support/packages.dart';
import '../support/scratches.dart';
import '../support/skipped_unless_modes_deny.dart';
import '../support/spy_runner.dart';
import '../support/waiting_into.dart';

void main() {
  late Directory temp;
  late SpyRunner runner;
  late Origin origin;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('muster-');
    runner = .new(hermetic(temp));
    origin = await .make(temp, runner);
  });

  tearDown(() => temp.delete(recursive: true));

  /// Three commits on `main`, each holding the package `app` and a file of
  /// its own, the codebase `app` pinned at the last.
  Future<(GitCodebase, List<Commit>)> history({String root = '.'}) async {
    final List<Commit> commits = [];
    Commit? parent;
    for (int i = 0; i < 3; i++) {
      parent = await origin.commit(parent, {
        ...packageFiles('app', at: root),
        'only$i.txt': 'commit $i\n',
      });
      commits.add(parent);
    }
    await origin.ref('refs/heads/main', commits.last);
    return (codebaseOf(origin, commits.last, root: root), commits);
  }

  Future<Muster> loaded(List<GitCodebase> codebases, {Runner? by}) async {
    await writeManifest(atRoot(temp), codebases);
    final Load load = await loaderIn(temp, by ?? runner).load();
    return switch (load) {
      Loaded(:final Muster muster) => muster,
      Refused(:final LoadRefusal reason) => fail('refused: $reason'),
    };
  }

  Future<Scratch> scratchOf(Muster muster, String name) async {
    final Scratching made = await muster.scratch(.parse(name)!);
    return switch (made) {
      Scratched(:final Scratch scratch) => scratch,
      NotNamed() || NotGit() || ScratchFailed() => fail('$made'),
    };
  }

  test('a consumer checks out older commits in a scratch while its checkout '
      'stays at its pin', () async {
    final (GitCodebase app, List<Commit> commits) = await history();
    final Muster muster = await loaded([app]);
    final Map<String, String> checkout = await filesUnder(
      checkoutAt(temp, 'app'),
    );
    final Scratch scratch = await scratchOf(muster, 'app');
    for (final int i in [0, 1, 0]) {
      expect(await scratch.move(commits[i]), isA<Moved>());
      expect(await filesUnder(scratch.package.path), {
        ...packageFiles('app'),
        'only$i.txt': 'commit $i\n',
      });
      expect(await headOf(scratch.package.path, runner), commits[i].hash);
      expect(await filesUnder(checkoutAt(temp, 'app')), checkout);
      expect(await headOf(checkoutAt(temp, 'app'), runner), app.commit.hash);
    }
    runner.commands.clear();
    expect(
      await loaderIn(temp, runner).load(),
      loadedWith({'app': fetchedAt(checkoutAt(temp, 'app'))}),
    );
    expect(runner.given, isNot(contains(contains('worktree add'))));
    expect(runner.given, isNot(contains(contains('checkout'))));
  });

  test('a scratch is made at its pin, its package at the root inside it, in '
      'a directory of its own under the temporary directory', () async {
    final (GitCodebase app, _) = await history(root: 'packages/app');
    final Muster muster = await loaded([app]);
    final Scratch scratch = await scratchOf(muster, 'app');
    final String top = p.dirname(p.dirname(scratch.package.path));
    expect(p.isWithin(scratchesIn(temp).path, top), isTrue);
    expect(p.basename(scratch.package.path), 'app');
    expect(await headOf(top, runner), app.commit.hash);
    expect(await filesUnder(top), {
      ...packageFiles('app', at: 'packages/app'),
      'only2.txt': 'commit 2\n',
    });
  });

  test('two scratches of one codebase each move apart', () async {
    final (GitCodebase app, List<Commit> commits) = await history();
    final Muster muster = await loaded([app]);
    final Scratch first = await scratchOf(muster, 'app');
    final Scratch second = await scratchOf(muster, 'app');
    expect(first.package.path, isNot(second.package.path));
    expect(await first.move(commits[0]), isA<Moved>());
    expect(await headOf(second.package.path, runner), app.commit.hash);
  });

  test('a move reverts every edit and removes every file the commit lacks, '
      'ignored ones among them', () async {
    final (GitCodebase app, List<Commit> commits) = await history();
    final Muster muster = await loaded([app]);
    final Scratch scratch = await scratchOf(muster, 'app');
    final String at = scratch.package.path;
    await File(p.join(at, 'only2.txt')).writeAsString('edited\n');
    await File(p.join(at, 'stray.txt')).writeAsString('stray\n');
    await File(p.join(at, '.dart_tool', 'out')).create(recursive: true);
    expect(await scratch.move(commits[1]), isA<Moved>());
    expect(await filesUnder(at), {
      ...packageFiles('app'),
      'only1.txt': 'commit 1\n',
    });
    expect(await Directory(p.join(at, '.dart_tool')).exists(), isFalse);
  });

  test('a move to a commit the clone lacks fetches it first', () async {
    final (GitCodebase app, List<Commit> commits) = await history();
    final Muster muster = await loaded([app]);
    final Scratch scratch = await scratchOf(muster, 'app');
    final Commit later = await origin.commit(commits.last, {'later.txt': ''});
    await origin.ref('refs/heads/later', later);
    expect(await scratch.move(later), isA<Moved>());
    expect(await filesUnder(scratch.package.path), {'later.txt': ''});
  });

  test('a move to a commit on none of its branches or tags fails as '
      'PinMissing, the scratch where it was', () async {
    final (GitCodebase app, _) = await history();
    final Muster muster = await loaded([app]);
    final Scratch scratch = await scratchOf(muster, 'app');
    final Commit stray = await origin.commit(null, {'stray.txt': ''});
    expect(
      await scratch.move(stray),
      isA<MoveFailed>().having(
        (MoveFailed m) => m.failure,
        'failure',
        isA<PinMissing>().having((PinMissing m) => m.commit, 'commit', stray),
      ),
    );
    expect(await headOf(scratch.package.path, runner), app.commit.hash);
  });

  test('a disposal removes the scratch and its clone keeps no record of it, '
      'and a second disposal removes nothing', () async {
    final (GitCodebase app, _) = await history();
    final Muster muster = await loaded([app]);
    final Scratch scratch = await scratchOf(muster, 'app');
    expect(await scratch.dispose(), isA<Disposed>());
    expect(await Directory(scratch.package.path).exists(), isFalse);
    expect(await worktreesOf(cloneOf(temp, app), runner), [
      await resolvedCheckout(temp, 'app'),
    ]);
    expect(await scratch.dispose(), isA<Disposed>());
  });

  test('a scratch deleted by hand is disposed of, its record pruned', () async {
    final (GitCodebase app, _) = await history();
    final Muster muster = await loaded([app]);
    final Scratch scratch = await scratchOf(muster, 'app');
    await Directory(scratch.package.path).delete(recursive: true);
    expect(await scratch.dispose(), isA<Disposed>());
    expect(await worktreesOf(cloneOf(temp, app), runner), [
      await resolvedCheckout(temp, 'app'),
    ]);
  });

  test('a disposal that cannot delete the scratch fails as StoreFailed, and '
      'one that can after is Disposed', () async {
    if (await skippedUnlessModesDeny(temp)) {
      return;
    }
    final (GitCodebase app, _) = await history();
    final Muster muster = await loaded([app]);
    final Scratch scratch = await scratchOf(muster, 'app');
    final Directory locked = await Directory(
      p.join(scratch.package.path, 'locked'),
    ).create();
    await File(p.join(locked.path, 'kept.txt')).writeAsString('');
    await chmod('500', locked);
    try {
      expect(
        await scratch.dispose(),
        isA<DisposalFailed>().having(
          (DisposalFailed d) => d.failure,
          'failure',
          isA<StoreFailed>(),
        ),
      );
    } finally {
      await chmod('700', locked);
    }
    expect(await scratch.dispose(), isA<Disposed>());
    expect(await Directory(scratch.package.path).exists(), isFalse);
  });

  test(
    'a disposal whose prune cannot start git fails as Unstartable',
    () async {
      final (GitCodebase app, _) = await history();
      final Muster muster = await loaded([app]);
      final Scratch scratch = await scratchOf(muster, 'app');
      runner.before = (Command command) async {
        if (command.arguments.contains('prune')) {
          throw const StoreFault(Unstartable(.git));
        }
      };
      expect(
        await scratch.dispose(),
        isA<DisposalFailed>().having(
          (DisposalFailed d) => d.failure,
          'failure',
          isA<Unstartable>(),
        ),
      );
    },
  );

  test('a name no codebase of the load bears is NotNamed', () async {
    final (GitCodebase app, _) = await history();
    final Muster muster = await loaded([app]);
    expect(
      await muster.scratch(.parse('other')!),
      isA<NotNamed>().having(
        (NotNamed n) => n.name,
        'name',
        CodebaseName.parse('other'),
      ),
    );
  });

  test('a scratch is made whatever the checkout gave, its clone made where '
      'the cache lacks it', () async {
    final (GitCodebase app, _) = await history();
    final Commit unlocked = await origin.commit(
      null,
      packageFiles('app', locked: false),
    );
    await origin.ref('refs/heads/unlocked', unlocked);
    final Muster muster = await loaded([
      codebaseOf(origin, unlocked, name: 'bare'),
      app,
    ]);
    await Directory(cloneOf(temp, app).path).delete(recursive: true);
    final Scratch scratch = await scratchOf(muster, 'bare');
    expect(await headOf(scratch.package.path, runner), unlocked.hash);
  });

  test('a scratch whose pin is on none of its branches or tags fails as '
      'PinMissing, leaving no directory', () async {
    final Commit stray = await origin.commit(null, packageFiles('app'));
    final Muster muster = await loaded([codebaseOf(origin, stray)]);
    expect(
      await muster.scratch(.parse('app')!),
      isA<ScratchFailed>().having(
        (ScratchFailed s) => s.failure,
        'failure',
        isA<PinMissing>(),
      ),
    );
    expect(await scratchesLeft(temp), isEmpty);
  });

  test('a scratch whose URL is no repo fails as CommandFailed, leaving no '
      'directory', () async {
    final (GitCodebase app, _) = await history();
    final Muster muster = await loaded([
      (
        name: app.name,
        url: .parse(p.join(temp.path, 'nowhere'))!,
        commit: app.commit,
        root: app.root,
        toolchain: app.toolchain,
      ),
    ]);
    expect(
      await muster.scratch(app.name),
      isA<ScratchFailed>().having(
        (ScratchFailed s) => s.failure,
        'failure',
        isA<CommandFailed>(),
      ),
    );
    expect(await scratchesLeft(temp), isEmpty);
  });

  test('a scratch that cannot start git fails as Unstartable', () async {
    final (GitCodebase app, _) = await history();
    final Muster muster = await loaded([app], by: unstartableIn(temp));
    expect(
      await muster.scratch(app.name),
      isA<ScratchFailed>().having(
        (ScratchFailed s) => s.failure,
        'failure',
        isA<Unstartable>().having(
          (Unstartable u) => u.executable,
          'executable',
          Executable.git,
        ),
      ),
    );
    expect(await scratchesLeft(temp), isEmpty);
  });

  test('a scratch whose temporary directory cannot be made fails as '
      'StoreFailed', () async {
    final (GitCodebase app, _) = await history();
    final Muster muster = await loaded([app]);
    await File(scratchesIn(temp).path).writeAsString('');
    expect(
      await muster.scratch(app.name),
      isA<ScratchFailed>().having(
        (ScratchFailed s) => s.failure,
        'failure',
        isA<StoreFailed>(),
      ),
    );
  });

  test("a scratch waits on a load's claim on its clone", () async {
    final (GitCodebase app, _) = await history();
    final Completer<void> waiting = .new();
    await writeManifest(atRoot(temp), [app]);
    final Load load = await loaderIn(
      temp,
      runner,
      claims: waitingInto(waiting),
    ).load();
    final Muster muster = (load as Loaded).muster;
    runner.commands.clear();
    late final Future<Scratching> made;
    await Claims(testLocker).holding(cloneOf(temp, app).claim, () async {
      made = muster.scratch(app.name);
      await waiting.future;
      expect(runner.given, isNot(contains(contains('worktree add'))));
    });
    expect(await made, isA<Scratched>());
  });
}

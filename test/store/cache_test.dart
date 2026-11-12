import 'dart:async';
import 'dart:io';

import 'package:muster/src/model/clone_path.dart';
import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/fetch_outcome.dart';
import 'package:muster/src/model/git_url.dart';
import 'package:muster/src/store/cache.dart';
import 'package:muster/src/store/claims.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/chmod.dart';
import '../support/faults.dart';
import '../support/git.dart';
import '../support/locker.dart';
import '../support/origin.dart';
import '../support/spy_runner.dart';

void main() {
  late Directory temp;
  late SpyRunner runner;
  late Origin origin;
  late Cache cache;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
    runner = .new(hermetic(temp));
    origin = await .make(temp, runner);
    cache = cacheIn(temp, runner);
  });

  tearDown(() => temp.delete(recursive: true));

  /// What the cache's directory holds, by name.
  Future<List<String>> cached() async => [
    await for (final FileSystemEntity entity in Directory(
      cache.directory.path,
    ).list())
      p.basename(entity.path),
  ];

  /// The name of [url]'s temporary clone, left in the cache with a file of
  /// git's in it, as a make cut short leaves one.
  Future<String> leftFor(GitUrl url) async {
    final String temporary = ClonePath.of(cache.directory, url).temporary.path;
    await File(p.join(temporary, 'HEAD')).create(recursive: true);
    return p.basename(temporary);
  }

  /// A commit on `main`, at its tip.
  Future<Commit> onMain([Commit? parent]) async {
    final Commit commit = await origin.commit(parent);
    await origin.ref('refs/heads/main', commit);
    return commit;
  }

  test('a pin on the default branch is in its clone after one call', () async {
    final Commit pin = await onMain();
    final ClonePath clone = await cache.clone(origin.url, pin);
    expect(await holds(clone.path, pin, runner), isTrue);
    expect(clone, ClonePath.of(cache.directory, origin.url));
  });

  test('a clone is bare, with no files of its pin checked out', () async {
    final ClonePath clone = await cache.clone(origin.url, await onMain());
    final String bare = (await runner.run((
      executable: .git,
      arguments: [
        '--git-dir=${clone.path}',
        'rev-parse',
        '--is-bare-repository',
      ],
    ))).stdout.trim();
    expect(bare, 'true');
  });

  test('a second call starts no fetch, and needs no origin', () async {
    final Commit pin = await onMain();
    final ClonePath first = await cache.clone(origin.url, pin);
    await origin.directory.delete(recursive: true);
    runner.commands.clear();
    expect(await cache.clone(origin.url, pin), first);
    expect(runner.fetched, isFalse);
  });

  test(
    'a pin the clone lacks is fetched, every branch and tag with it',
    () async {
      final Commit first = await onMain();
      await cache.clone(origin.url, first);
      final Commit later = await onMain(first);
      final Commit side = await origin.commit();
      await origin.tag('side', side, annotated: false);
      final ClonePath clone = await cache.clone(origin.url, later);
      expect(await holds(clone.path, later, runner), isTrue);
      expect(await holds(clone.path, side, runner), isTrue);
    },
  );

  test('a branch named under one the URL deleted is still reached', () async {
    final Commit first = await onMain();
    await origin.ref('refs/heads/release', first);
    await cache.clone(origin.url, first);
    await origin.delete('refs/heads/release');
    final Commit pin = await origin.commit(first);
    await origin.ref('refs/heads/release/1.x', pin);
    final ClonePath clone = await cache.clone(origin.url, pin);
    expect(await holds(clone.path, pin, runner), isTrue);
  });

  test('a branch moved by force still brings its new tip', () async {
    await cache.clone(origin.url, await onMain());
    final Commit rewritten = await onMain();
    final ClonePath clone = await cache.clone(origin.url, rewritten);
    expect(await holds(clone.path, rewritten, runner), isTrue);
  });

  test('two codebases of one URL share its clone, and another spelling of the '
      'same repo takes a clone of its own', () async {
    final Commit pin = await onMain();
    final ClonePath one = await cache.clone(origin.url, pin);
    expect(await cache.clone(origin.url, pin), one);
    final ClonePath other = await cache.clone(
      .parse('${origin.url.url}/')!,
      pin,
    );
    expect(other, isNot(one));
    expect(await holds(other.path, pin, runner), isTrue);
  });

  test('a SHA-256 repo\'s pin is in its clone', () async {
    final Origin sha256 = await .make(
      await .new(p.join(temp.path, 'sha256')).create(),
      runner,
      format: .sha256,
    );
    final Commit pin = await sha256.commit();
    await sha256.ref('refs/heads/main', pin);
    final ClonePath clone = await cache.clone(sha256.url, pin);
    expect(await holds(clone.path, pin, runner), isTrue);
  });

  test('a pin of the other hash\'s length leaves a clone the right pin still '
      'reaches', () async {
    final Commit pin = await onMain();
    await expectLater(
      cache.clone(origin.url, .parse('a' * 64)!),
      throwsA(storeFault(isA<PinMissing>())),
    );
    final ClonePath clone = await cache.clone(origin.url, pin);
    expect(await holds(clone.path, pin, runner), isTrue);
  });

  test(
    'a pin on no branch or tag of its URL is missing, naming both',
    () async {
      await onMain();
      final Commit pin = .parse('0' * 40)!;
      await expectLater(
        cache.clone(origin.url, pin),
        throwsA(
          storeFault(
            isA<PinMissing>()
                .having((PinMissing f) => f.url, 'url', origin.url)
                .having((PinMissing f) => f.commit, 'commit', pin),
          ),
        ),
      );
    },
  );

  test(
    'a commit reachable from no ref is missing, though its URL holds it',
    () async {
      await onMain();
      final Commit loose = await origin.commit();
      await expectLater(
        cache.clone(origin.url, loose),
        throwsA(storeFault(isA<PinMissing>())),
      );
    },
  );

  test('an annotated tag\'s own hash is no commit, and is missing', () async {
    final Commit main = await onMain();
    await origin.tag('v1', main, annotated: true);
    final Commit tag = .parse(await origin.resolve('refs/tags/v1'))!;
    expect(tag, isNot(main));
    await expectLater(
      cache.clone(origin.url, tag),
      throwsA(storeFault(isA<PinMissing>())),
    );
  });

  test('a URL git cannot clone fails, carrying git\'s command and output, and '
      'leaves nothing in the cache', () async {
    final GitUrl gone = .parse(p.join(temp.path, 'gone'))!;
    await expectLater(
      cache.clone(gone, .parse('a' * 40)!),
      throwsA(
        storeFault(
          isA<CommandFailed>()
              .having(
                (CommandFailed f) => f.command.arguments,
                'arguments',
                contains('clone'),
              )
              .having((CommandFailed f) => f.stderr, 'stderr', isNotEmpty),
        ),
      ),
    );
    expect(await cached(), isEmpty);
  });

  test('a failed clone leaves the next call free to clone', () async {
    final Directory later = .new(p.join(temp.path, 'later'));
    final GitUrl url = .parse(p.join(later.path, 'origin'))!;
    await expectLater(
      cache.clone(url, .parse('a' * 40)!),
      throwsA(storeFault(isA<CommandFailed>())),
    );
    final Origin made = await .make(await later.create(), runner);
    final Commit pin = await made.commit();
    await made.ref('refs/heads/main', pin);
    final ClonePath clone = await cache.clone(url, pin);
    expect(await holds(clone.path, pin, runner), isTrue);
  });

  test('a clone that cannot move into place fails, naming the path, and '
      'leaves nothing of its own in the cache', () async {
    final ClonePath clone = .of(cache.directory, origin.url);
    await File(clone.path).create(recursive: true);
    await expectLater(
      cache.clone(origin.url, await onMain()),
      throwsA(storeFault(isA<StoreFailed>())),
    );
    expect(await cached(), [p.basename(clone.path)]);
  });

  test('a temporary clone its own URL\'s make left is removed, and the clone '
      'made afresh', () async {
    final Commit pin = await onMain();
    await leftFor(origin.url);
    final ClonePath clone = await cache.clone(origin.url, pin);
    expect(await holds(clone.path, pin, runner), isTrue);
    expect(await cached(), [p.basename(clone.path)]);
  });

  test('a temporary clone another URL\'s make left, its claim held by no '
      'one, is removed by a clone the cache already holds', () async {
    final Commit pin = await onMain();
    await cache.clone(origin.url, pin);
    final String left = await leftFor(.parse('https://example.com/left.git')!);
    runner.commands.clear();
    await cache.clone(origin.url, pin);
    expect(await cached(), isNot(contains(left)));
    expect(runner.fetched, isFalse);
  });

  test('a temporary clone whose claim another hold has is left to it, and '
      'never waited on', () async {
    final GitUrl other = .parse('https://example.com/held.git')!;
    final String left = await leftFor(other);
    final Completer<void> held = .new();
    final Completer<void> go = .new();
    final Future<void> holder = Claims(testLocker)
        .holding(ClonePath.of(cache.directory, other).claim, () {
          held.complete();
          return go.future;
        });
    await held.future;
    final Cache neverWaiting = cacheIn(
      temp,
      runner,
      .new(testLocker, () async => fail('a held claim was waited on')),
    );
    await neverWaiting.clone(origin.url, await onMain());
    expect(await cached(), contains(left));
    go.complete();
    await holder;
  });

  test('an entry of the cache that is no temporary clone is left', () async {
    final List<String> others = [
      p.basename(
        ClonePath.of(
          cache.directory,
          .parse('https://example.com/b.git')!,
        ).path,
      ),
      '.clone-abc123',
      'notes.partial',
    ];
    for (final String other in others) {
      await Directory(p.join(cache.directory.path, other))
          .create(recursive: true);
    }
    final ClonePath clone = await cache.clone(origin.url, await onMain());
    expect(
      await cached(),
      unorderedEquals([...others, p.basename(clone.path)]),
    );
  });

  test('a temporary clone that cannot be removed fails the clone, naming '
      'the path', () async {
    final String left = await leftFor(.parse('https://example.com/left.git')!);
    final Directory locked = await Directory(
      p.join(cache.directory.path, left, 'objects'),
    ).create();
    await File(p.join(locked.path, 'pack')).create();
    await chmod('555', locked);
    try {
      await expectLater(
        cache.clone(origin.url, await onMain()),
        throwsA(
          storeFault(
            isA<StoreFailed>().having(
              (StoreFailed f) => f.path,
              'path',
              startsWith(p.join(cache.directory.path, left)),
            ),
          ),
        ),
      );
    } finally {
      await chmod('755', locked);
    }
  });

  test('a cache that cannot be made fails, naming the path', () async {
    final File blocker = await .new(p.join(temp.path, 'file')).create();
    final Cache blocked = .new(
      .of((
        variables: {'MUSTER_CACHE': p.join(blocker.path, 'cache')},
        os: .posix,
      ))!,
      runner,
      .new(testLocker),
    );
    await expectLater(
      blocked.clone(origin.url, await onMain()),
      throwsA(
        storeFault(
          isA<StoreFailed>().having(
            (StoreFailed f) => f.path,
            'path',
            startsWith(blocker.path),
          ),
        ),
      ),
    );
  });

  test('git that cannot start fails, naming git', () async {
    final Cache unstartable = cacheIn(
      temp,
      .new({...hermetic(temp), 'PATH': '/muster-no-such-directory'}),
    );
    await expectLater(
      unstartable.clone(origin.url, .parse('a' * 40)!),
      throwsA(storeFault(isA<Unstartable>())),
    );
  });

  test(
    'a GIT_DIR and GIT_OBJECT_DIRECTORY in the environment, as a hook '
    'exports, move no other repo, and the clone itself holds the pin',
    () async {
      final Directory mine = await .new(p.join(temp.path, 'mine')).create();
      final Origin other = await .make(mine, runner);
      final Commit own = await other.commit();
      await other.ref('refs/heads/main', own);
      final Commit pin = await onMain();
      final ClonePath clone = await cacheIn(
        temp,
        .new({
          ...hermetic(temp),
          'GIT_DIR': other.directory.path,
          'GIT_OBJECT_DIRECTORY': p.join(other.directory.path, 'objects'),
        }),
      ).clone(origin.url, pin);
      expect(await holds(clone.path, pin, runner), isTrue);
      expect(await other.resolve('refs/heads/main'), own.hash);
    },
  );

  test(
    'a bare clone is reached where safe.bareRepository is explicit',
    () async {
      final Map<String, String> environment = hermetic(temp);
      await File(environment['GIT_CONFIG_GLOBAL']!)
          .writeAsString('[safe]\n\tbareRepository = explicit\n');
      final Commit pin = await onMain();
      final ClonePath clone = await cacheIn(
        temp,
        .new(environment),
      ).clone(origin.url, pin);
      expect(await holds(clone.path, pin, runner), isTrue);
    },
  );
}

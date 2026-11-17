import 'dart:convert';
import 'dart:io';

import 'package:muster/src/model/command.dart';
import 'package:muster/src/model/executable.dart';
import 'package:muster/src/model/fetch_outcome.dart';
import 'package:muster/src/store/ran.dart';
import 'package:muster/src/store/runner.dart';
import 'package:test/test.dart';

import '../support/chmod.dart';
import '../support/faults.dart';

/// A git command that prints, through the shell, three variables of its
/// process's environment a line each: `MUSTER_PROBE`, `GIT_TERMINAL_PROMPT`
/// and `HOME`, and no other, so a failure shows no secret.
const Command _probe = (
  executable: .git,
  arguments: [
    '-c',
    r'alias.muster-probe=!printf "%s\n" "$MUSTER_PROBE" "$GIT_TERMINAL_PROMPT" "$HOME"',
    'muster-probe',
  ],
);

/// A git command that exits 1 and writes nothing, for a key no file holds,
/// in any directory.
const Command _absent = (
  executable: .git,
  arguments: ['config', '--file', '/dev/null', '--get', 'muster.none'],
);

/// The three variables [ran] printed.
List<String> _printed(Ran ran) => ran.stdout.split('\n').take(3).toList();

/// Just enough of the test process's environment for git to start.
final Map<String, String> _path = {'PATH': Platform.environment['PATH']!};

void main() {
  test('a process reads the environment its runner was made with, and '
      'nothing else of the test process\'s', () async {
    final Ran ran = await Runner({..._path, 'MUSTER_PROBE': 'here'})
        .run(_probe);
    expect(_printed(ran), ['here', '0', '']);
  });

  /// An environment of the test's own choosing, so no launcher's own
  /// variables come into it, with the user's `PATH` and `HOME` for git and
  /// dart to start.
  final Map<String, String> handed = {
    ..._path,
    'HOME': Platform.environment['HOME']!,
    'USER': 'muster',
    'MUSTER_PROBE': 'here',
    'MUSTER_SPACED': 'two words',
  };

  /// What [handed] reaches each process as, past its `PATH`: every other
  /// variable of it, its prompts off and no askpass over it.
  final Map<String, String> reaches = {
    for (final MapEntry(:key, :value) in handed.entries)
      if (key != 'PATH') key: value,
    'GIT_TERMINAL_PROMPT': '0',
    'GIT_ASKPASS': '',
    'SSH_ASKPASS': 'false',
    'SSH_ASKPASS_REQUIRE': 'force',
  };

  /// Expects [printed], one `name=value` per line, to name every variable
  /// of [reaches] with its value, and a `PATH` that ends in the one handed
  /// in, since git puts its own directory ahead of it.
  void expectReached(String printed) {
    final Map<String, String> lines = {
      for (final String line in const LineSplitter().convert(printed))
        if (line.indexOf('=') case final int at when at > 0)
          line.substring(0, at): line.substring(at + 1),
    };
    expect({
      for (final String name in reaches.keys) name: lines[name],
    }, reaches);
    expect(lines['PATH'], endsWith(handed['PATH']!));
  }

  test('an environment handed in reaches git whole, with its prompts off and '
      'no askpass over it', () async {
    final Ran ran = await Runner(handed).run((
      executable: .git,
      arguments: ['-c', 'alias.muster-env=!env', 'muster-env'],
    ));
    expectReached(ran.stdout);
  });

  test('an environment handed in reaches dart whole, with its prompts off and '
      'no askpass over it', () async {
    final Directory temp = await .systemTemp.createTemp('muster-');
    addTearDown(() => temp.delete(recursive: true));
    final File script = await .new('${temp.path}/script.dart').writeAsString(
      "import 'dart:io';\n"
      'void main() {\n'
      '  for (final MapEntry(:key, :value) in Platform.environment.entries) {\n'
      "    print('\$key=\$value');\n"
      '  }\n'
      '}\n',
    );
    final Ran ran = await Runner(handed)
        .run((executable: .dart, arguments: [script.path]));
    expectReached(ran.stdout);
  });

  test('dart reads the environment its runner was made with, and nothing '
      'else', () async {
    final Directory temp = await .systemTemp.createTemp('muster-');
    addTearDown(() => temp.delete(recursive: true));
    final File script = await .new('${temp.path}/script.dart').writeAsString(
      "import 'dart:io';\n"
      "void main() => print(['MUSTER_PROBE', 'HOME', 'GIT_DIR']"
      ".map((String n) => Platform.environment[n] ?? '-').join(','));\n",
    );
    final Ran ran = await Runner({
      ..._path,
      'MUSTER_PROBE': 'here',
      'GIT_DIR': 'kept',
    }).run((executable: .dart, arguments: [script.path]));
    expect(ran.stdout.trim(), 'here,-,kept');
  });

  test('dart runs with its prompts off and no askpass, over the names its '
      'environment gives, so the git pub runs asks nothing either', () async {
    final Directory temp = await .systemTemp.createTemp('muster-');
    addTearDown(() => temp.delete(recursive: true));
    final File script = await .new('${temp.path}/script.dart').writeAsString(
      "import 'dart:io';\n"
      "void main() => print(['GIT_TERMINAL_PROMPT', 'GIT_ASKPASS', "
      "'SSH_ASKPASS', 'SSH_ASKPASS_REQUIRE']"
      ".map((String n) => '\$n=\${Platform.environment[n]}').join(','));\n",
    );
    final Ran ran = await Runner({
      ..._path,
      'GIT_ASKPASS': 'muster-asks',
      'SSH_ASKPASS': 'muster-asks',
      'SSH_ASKPASS_REQUIRE': 'never',
    }).run((executable: .dart, arguments: [script.path]));
    expect(
      ran.stdout.trim(),
      'GIT_TERMINAL_PROMPT=0,GIT_ASKPASS=,SSH_ASKPASS=false,'
      'SSH_ASKPASS_REQUIRE=force',
    );
  });

  test('git runs with its terminal prompt off', () async {
    final Ran ran = await Runner(_path).run(_probe);
    expect(_printed(ran)[1], '0');
  });

  test('the runner\'s environment wins over its own for git', () async {
    final Ran ran = await Runner({..._path, 'GIT_TERMINAL_PROMPT': '1'})
        .run(_probe);
    expect(_printed(ran)[1], '1');
  });

  test('git starts with none of the variables that tell it which repo it is '
      'in, every one git lists but the two that carry configuration', () async {
    final Directory temp = await .systemTemp.createTemp('muster-');
    addTearDown(() => temp.delete(recursive: true));
    final List<String> listed = (await Runner(_path).run((
      executable: .git,
      arguments: ['-C', temp.path, 'rev-parse', '--local-env-vars'],
    ))).stdout.trim().split('\n');
    final List<String> names = [
      for (final String name in listed)
        if (name != 'GIT_CONFIG_PARAMETERS' && name != 'GIT_CONFIG_COUNT') name,
    ];
    expect(names, containsAll(['GIT_DIR', 'GIT_PREFIX']));
    // A command of git's on `PATH` by its name, which git runs as it finds
    // it, since the shell of an alias reads the `GIT_PREFIX` git sets for it.
    final File command = await .new('${temp.path}/git-muster-repo')
        .writeAsString(
          '#!/bin/sh\n'
          'printf "%s\\n"${names.map((String n) => ' "\$$n"').join()}\n',
        );
    await chmod('+x', command);
    final Ran ran = await Runner({
      'PATH': '${temp.path}:${_path['PATH']}',
      for (final String name in names) name: 'muster-probe',
    }).run((executable: .git, arguments: ['-C', temp.path, 'muster-repo']));
    expect(ran.stdout.split('\n').take(names.length), [
      for (final String _ in names) '',
    ]);
  });

  test(
    'git keeps the configuration its caller passes in the environment',
    () async {
      final Ran ran =
          await Runner({
            ..._path,
            'GIT_CONFIG_COUNT': '1',
            'GIT_CONFIG_KEY_0': 'muster.counted',
            'GIT_CONFIG_VALUE_0': 'here',
            'GIT_CONFIG_PARAMETERS': "'muster.passed'='there'",
          }).run((
            executable: .git,
            arguments: [
              '-c',
              r'alias.muster-config=!git config --get muster.counted && git config --get muster.passed',
              'muster-config',
            ],
          ));
      expect(ran.stdout.split('\n').take(2), ['here', 'there']);
    },
  );

  test('output that is no UTF-8 is read, its bad bytes replaced', () async {
    final Ran ran = await Runner(_path).run((
      executable: .git,
      arguments: [
        '-c',
        r"alias.muster-bytes=!printf '\377muster'",
        'muster-bytes',
      ],
    ));
    expect(ran.stdout, '�muster');
  });

  test('a command that exits 0 returns what it wrote', () async {
    final Ran ran = await Runner(_path)
        .run((executable: .git, arguments: ['--version']));
    expect(ran.exitCode, 0);
    expect(ran.stdout, startsWith('git version'));
  });

  test('an exit code named among the exits returns', () async {
    final Ran ran = await Runner(_path).run(_absent, exits: const {0, 1});
    expect(ran.exitCode, 1);
  });

  test('a command that exits with a code it should not have fails, carrying '
      'the command, its exit code and its output', () async {
    const Command bad = (executable: .git, arguments: ['muster-no-such-verb']);
    await expectLater(
      Runner(_path).run(bad),
      throwsA(
        storeFault(
          isA<CommandFailed>()
              .having((CommandFailed f) => f.command, 'command', bad)
              .having((CommandFailed f) => f.exitCode, 'exitCode', isNot(0))
              .having(
                (CommandFailed f) => f.stderr,
                'stderr',
                contains('muster-no-such-verb'),
              ),
        ),
      ),
    );
  });

  test('a code left out of the exits fails, even 0\'s neighbour 1', () async {
    await expectLater(
      Runner(_path).run(_absent),
      throwsA(
        storeFault(
          isA<CommandFailed>()
              .having((CommandFailed f) => f.exitCode, 'exitCode', 1)
              .having((CommandFailed f) => f.stdout, 'stdout', isEmpty),
        ),
      ),
    );
  });

  test('an executable that cannot start fails, naming it', () async {
    await expectLater(
      Runner({'PATH': '/muster-no-such-directory'}).run(_probe),
      throwsA(
        storeFault(
          isA<Unstartable>().having(
            (Unstartable f) => f.executable,
            'executable',
            Executable.git,
          ),
        ),
      ),
    );
  });
}

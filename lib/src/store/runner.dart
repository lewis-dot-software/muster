import 'dart:convert';
import 'dart:io';

import '../model/command.dart';
import '../model/executable.dart';
import '../model/fetch_failure.dart';
import 'ran.dart';
import 'store_fault.dart';

/// Starts every process muster runs, each with the environment the runner was
/// made with and nothing else.
///
/// Git starts with none of the variables that point it at a repo of its
/// caller's, such as the `GIT_DIR` a hook exports, so it acts on the repo
/// muster names alone, and keeps those that carry its caller's
/// configuration, as git itself does on moving to another repo. It runs with its terminal prompt off, so where it
/// would ask on the terminal for an HTTP URL's credentials it fails instead,
/// unless the environment sets `GIT_TERMINAL_PROMPT` itself.
class Runner {
  /// The runner that starts each process with [environment], the whole of
  /// what it reads.
  Runner(Map<String, String> environment)
    : _environment = .unmodifiable(environment);

  final Map<String, String> _environment;

  /// Runs [command] to its exit, and returns what it left where its exit code
  /// is one of [exits].
  ///
  /// Throws a [StoreFault] of [CommandFailed] where it exits with any other
  /// code, and of [Unstartable] where its executable cannot start.
  Future<Ran> run(Command command, {Set<int> exits = const {0}}) async {
    final ProcessResult result;
    try {
      result = await Process.run(
        command.executable.name,
        command.arguments,
        environment: _for(command.executable),
        includeParentEnvironment: false,
        stdoutEncoding: _output,
        stderrEncoding: _output,
      );
    } on ProcessException {
      throw StoreFault(Unstartable(command.executable));
    }
    final Ran ran = (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
    if (!exits.contains(ran.exitCode)) {
      throw StoreFault(
        CommandFailed(command, ran.exitCode, ran.stdout, ran.stderr),
      );
    }
    return ran;
  }

  Map<String, String> _for(Executable executable) => switch (executable) {
    .git => {
      'GIT_TERMINAL_PROMPT': '0',
      for (final MapEntry<String, String>(:key, :value) in _environment.entries)
        if (!_gitRepoVariables.contains(key)) key: value,
    },
    .dart || .flutter => _environment,
  };
}

/// The variables that tell git which repo it is in: those
/// `git rev-parse --local-env-vars` lists, less `GIT_CONFIG_PARAMETERS` and
/// `GIT_CONFIG_COUNT`, which carry configuration and name no repo.
const Set<String> _gitRepoVariables = {
  'GIT_ALTERNATE_OBJECT_DIRECTORIES',
  'GIT_CONFIG',
  'GIT_OBJECT_DIRECTORY',
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_IMPLICIT_WORK_TREE',
  'GIT_GRAFT_FILE',
  'GIT_INDEX_FILE',
  'GIT_NO_REPLACE_OBJECTS',
  'GIT_REPLACE_REF_BASE',
  'GIT_PREFIX',
  'GIT_SHALLOW_FILE',
  'GIT_COMMON_DIR',
};

/// Output decoded as UTF-8, a byte that is none read as a replacement
/// character, since git writes paths and messages in whatever bytes they hold.
const Utf8Codec _output = .new(allowMalformed: true);

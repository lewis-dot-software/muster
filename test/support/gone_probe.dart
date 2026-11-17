// A program that writes the script it was started from to its error stream,
// deletes its own working directory, then runs the verb its first argument
// names on the manifests the rest name, as the process muster runs in. It
// writes the case of the refusal where the run refuses, and where it does
// not, the names of the codebases it gave an outcome, as a JSON list.

import 'dart:convert';
import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/cli/verb.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/load/process_loads.dart';
import 'package:muster/src/model/lock_outcome.dart';

import 'refusal_case.dart';

Future<void> main(List<String> arguments) async {
  stderr.writeln(Platform.script);
  Directory.current.deleteSync();
  final List<String> manifests = arguments.skip(1).toList();
  stdout.write(switch (Verb.values.byName(arguments.first)) {
    .fetch => switch (await Muster.load(manifests: manifests)) {
      Refused(:final LoadRefusal reason) => RefusalCase.of(reason).name,
      Loaded(:final Map<CodebaseName, FetchOutcome> outcomes) => _names(
        outcomes.keys,
      ),
    },
    .lock => switch (await const ProcessLoads().lock(named: manifests)) {
      LockRefused(:final LoadRefusal reason) => RefusalCase.of(reason).name,
      Locked(:final Map<CodebaseName, LockOutcome> outcomes) => _names(
        outcomes.keys,
      ),
    },
  });
}

String _names(Iterable<CodebaseName> names) =>
    jsonEncode([for (final CodebaseName name in names) name.name]);

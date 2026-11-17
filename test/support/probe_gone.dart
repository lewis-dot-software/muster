import 'dart:io';

import 'package:muster/src/cli/verb.dart';
import 'package:path/path.dart' as p;

import 'refusal_case.dart';
import 'support_program.dart';

/// What a process whose working directory is gone writes, running [verb] on
/// the manifest at [manifest]: the name of the refusal's [RefusalCase] where
/// the run refuses, and the script it was started from on its error stream's
/// first line. Its working directory is made in [temp] before the process
/// deletes it.
Future<ProcessResult> probeGone(
  Directory temp,
  Verb verb,
  String manifest,
) async {
  final List<String> started = await SupportProgram.gone.started([
    verb.name,
    manifest,
  ]);
  final Directory gone = await .new(p.join(temp.path, 'gone')).create();
  return Process.run(
    Platform.resolvedExecutable,
    started,
    workingDirectory: gone.path,
  );
}

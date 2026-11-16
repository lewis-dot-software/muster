import 'dart:io';

import 'package:muster/src/cli/verb.dart';
import 'package:path/path.dart' as p;

import 'loads.dart';
import 'support_program.dart';

/// What a process whose working directory is gone writes, running [verb] on
/// the manifest at [manifest]: the refusal's type where the run refuses, and
/// the script it was started from on its error stream's first line.
/// Its working directory is made in [temp] before the process deletes it.
Future<ProcessResult> probeGone(
  Directory temp,
  Verb verb,
  String manifest,
) async {
  final String program = await SupportProgram.gone.kernel();
  final Directory gone = await Directory(p.join(temp.path, 'gone')).create();
  return Process.run(Platform.resolvedExecutable, [
    '--packages=${packagesOf(await musterRoot())}',
    program,
    verb.name,
    manifest,
  ], workingDirectory: gone.path);
}

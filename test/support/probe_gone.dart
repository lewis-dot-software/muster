import 'dart:io';

import 'package:muster/src/cli/verb.dart';
import 'package:path/path.dart' as p;

import 'loads.dart';

/// What a process whose working directory is gone writes, running [verb] on
/// the manifest at [manifest]: the refusal's type where the run refuses.
/// Its working directory is made in [temp] before the process deletes it.
Future<ProcessResult> probeGone(
  Directory temp,
  Verb verb,
  String manifest,
) async {
  final String muster = await musterRoot();
  final Directory gone = await Directory(p.join(temp.path, 'gone')).create();
  return Process.run(Platform.resolvedExecutable, [
    '--packages=${p.join(muster, '.dart_tool', 'package_config.json')}',
    p.join(muster, 'test', 'support', 'gone_probe.dart'),
    verb.name,
    manifest,
  ], workingDirectory: gone.path);
}

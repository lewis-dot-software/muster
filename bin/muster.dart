import 'dart:io';

import 'package:muster/src/cli/cli.dart';
import 'package:muster/src/cli/exit_code.dart';
import 'package:muster/src/load/process_loads.dart';

/// Runs the `muster` command line [arguments] name, in the process as it
/// stands, and exits with its code.
Future<void> main(List<String> arguments) async {
  final ExitCode code = await Cli(
    const ProcessLoads(),
    stdout,
    stderr,
  ).run(arguments);
  exitCode = code.code;
}

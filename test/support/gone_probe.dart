// A program that deletes its own working directory, then runs the verb its
// first argument names on the manifests the rest name, as the process muster
// runs in, writing the refusal's type where the run refuses, and the run
// whole where it does not. Started by `probeGone` alone.

import 'dart:io';

import 'package:muster/muster.dart';
import 'package:muster/src/cli/verb.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/load/process_loads.dart';

Future<void> main(List<String> arguments) async {
  Directory.current.deleteSync();
  final List<String> manifests = arguments.skip(1).toList();
  stdout.write(switch (Verb.values.byName(arguments.first)) {
    .fetch => switch (await Muster.load(manifests: manifests)) {
      Refused(:final LoadRefusal reason) => '${reason.runtimeType}',
      final Loaded loaded => '$loaded',
    },
    .lock => switch (await const ProcessLoads().lock(named: manifests)) {
      LockRefused(:final LoadRefusal reason) => '${reason.runtimeType}',
      final Locked locked => '$locked',
    },
  });
}

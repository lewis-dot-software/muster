import 'dart:io';

import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/model/commit.dart';
import 'package:muster/src/model/consumer_root.dart';
import 'package:muster/src/model/git_codebase.dart';
import 'package:muster/src/model/locks_directory.dart';
import 'package:muster/src/model/toolchain.dart';
import 'package:muster/src/store/checkouts.dart';
import 'package:muster/src/store/runner.dart';
import 'package:path/path.dart' as p;

import 'git.dart';
import 'origin.dart';

/// The pubspec of a package named [name] with no dependencies, which
/// resolves with no network.
String pubspecOf(String name) => 'name: $name\nenvironment:\n  sdk: ^3.0.0\n';

/// The lock a package of [pubspecOf] resolves to, which
/// `pub get --enforce-lockfile` holds it to.
const String lockText = 'packages: {}\nsdks:\n  dart: ">=3.0.0 <4.0.0"\n';

/// The files of a package named [name] in the directory [at] of its repo,
/// `.` for the top, its lock among them where [locked] holds.
Map<String, String> packageFiles(
  String name, {
  String at = '.',
  bool locked = true,
}) => {
  p.posix.normalize('$at/pubspec.yaml'): pubspecOf(name),
  if (locked) p.posix.normalize('$at/pubspec.lock'): lockText,
};

/// The path of [file] in [checkout], given relative to its top in `/`
/// separators.
String fileIn(CheckoutPath checkout, String file) =>
    p.joinAll([checkout.path, ...file.split('/')]);

/// The consumer's root in [temp], under which its checkouts stand.
ConsumerRoot consumerIn(Directory temp) =>
    .new(p.join(temp.path, 'consumer'), .posix);

/// The checkouts of a consumer in [temp], cloned into a cache there, their
/// processes run by [runner].
Checkouts checkoutsIn(Directory temp, Runner runner) =>
    .new(consumerIn(temp), cacheIn(temp, runner), runner, .new(.posix));

/// The kept locks of the consumer's `muster.yaml` in [temp].
LocksDirectory locksIn(Directory temp) =>
    .beside(.parse(p.join(consumerIn(temp).path, 'muster.yaml'), .posix)!);

/// The codebase [name] of [origin], pinned at [commit], its [root] and
/// [toolchain] as given.
GitCodebase codebaseOf(
  Origin origin,
  Commit commit, {
  String name = 'app',
  String root = '.',
  Toolchain toolchain = .dart,
}) => (
  name: .parse(name)!,
  url: origin.url,
  commit: commit,
  root: .parse(root)!,
  toolchain: toolchain,
);

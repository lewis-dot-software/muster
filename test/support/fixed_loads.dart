import 'package:muster/muster.dart';
import 'package:muster/src/load/loads.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/store/cache.dart';
import 'package:muster/src/store/claims.dart';
import 'package:muster/src/store/runner.dart';
import 'package:muster/src/store/scratches.dart';

import 'locker.dart';

/// Runs that give what they were made with, starting no process and
/// touching no file, keeping the manifests each was named.
class FixedLoads implements Loads {
  /// The runs whose every load gives [loads] and every lock [locks].
  FixedLoads({Load? loads, Locking? locks})
    : _loads = loads ?? Loaded(_muster, const {}),
      _locks = locks ?? const Locked({}, []);

  /// The runs whose every load gives [outcomes].
  FixedLoads.loading(Map<CodebaseName, FetchOutcome> outcomes)
    : this(loads: Loaded(_muster, outcomes));

  final Load _loads;

  final Locking _locks;

  /// The manifests each run was named, in order.
  final List<List<String>> named = [];

  @override
  Future<Load> load({List<String> named = const [], String? root}) async {
    this.named.add(named);
    return _loads;
  }

  @override
  Future<Locking> lock({List<String> named = const [], String? root}) async {
    this.named.add(named);
    return _locks;
  }
}

/// A muster of no codebase, whose scratches nothing makes.
final Muster _muster = .new(
  const {},
  Scratches(
    Cache(
      .of((variables: {'MUSTER_CACHE': '/cache'}, os: .posix))!,
      _none,
      _claims,
    ),
    _none,
    _claims,
    .new('/temp', .posix),
  ),
);

final Runner _none = .new(const {});

final Claims _claims = .new(testLocker);

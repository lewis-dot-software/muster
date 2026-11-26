import 'package:muster/muster.dart';
import 'package:muster/src/load/locking.dart';
import 'package:muster/src/load/process_loads.dart';
import 'package:test/test.dart';

import '../support/loads.dart';

void main() {
  test('a load on a POSIX system muster takes no claim on refuses, naming '
      'the system, before the manifests are sought', () async {
    expect(
      await ProcessLoads(system: () => 'freebsd')
          .load(named: ['/muster-no-such-directory/muster.yaml']),
      refusedFor(
        isA<NoClaim>().having((NoClaim n) => n.system, 'system', 'freebsd'),
      ),
    );
  });

  test('a lock run on a POSIX system muster takes no claim on refuses, '
      'naming the system, before the manifests are sought', () async {
    expect(
      await ProcessLoads(system: () => 'freebsd')
          .lock(named: ['/muster-no-such-directory/muster.yaml']),
      isA<LockRefused>().having(
        (LockRefused r) => r.reason,
        'reason',
        isA<NoClaim>().having((NoClaim n) => n.system, 'system', 'freebsd'),
      ),
    );
  });
}

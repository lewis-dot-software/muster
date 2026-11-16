import 'dart:io';

import 'package:grit/grit.dart';
import 'package:muster/src/store/kernel.dart';
import 'package:muster/src/store/locker.dart';
import 'package:test/test.dart';

void main() {
  test('a kernel is named by the system dart:io names, macos and linux '
      'alone', () {
    expect(Kernel.named('macos'), Kernel.darwin);
    expect(Kernel.named('linux'), Kernel.linux);
    for (final String system in [
      'freebsd',
      'android',
      'ios',
      'fuchsia',
      'windows',
      'Linux',
      '',
    ]) {
      expect(Kernel.named(system), isNull, reason: system);
    }
  });

  property('no system but macos and linux names a kernel', (Draw draw) {
    final String system = draw(
      .string(alphabet: .lettersAndDigits),
      label: 'system',
    );
    if (system != 'macos' && system != 'linux') {
      expect(Kernel.named(system), isNull);
    }
  });

  test('a POSIX system muster knows no C library of has no locker', () {
    expect(Locker.of(.posix, 'freebsd'), isNull);
  });

  test("a POSIX system muster knows takes flock's lock, its C library "
      'bound', () {
    expect(Locker.of(.posix, Platform.operatingSystem), isA<FlockLocker>());
  });

  test("Windows takes LockFileEx's lock whatever its name", () {
    expect(Locker.of(.windows, 'freebsd'), isA<LockFileExLocker>());
  });
}

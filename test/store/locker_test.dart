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

  property("STO-26: `macos` names Darwin's kernel, `linux` names Linux's, and "
      'no other system names one.', (Draw draw) {
    final String name = draw(.element(['macos', 'linux']), label: 'name');
    final String system = draw(
      .oneOf([
        .element([name]),
        .element([
          name.toUpperCase(),
          '${name[0].toUpperCase()}${name.substring(1)}',
          name.substring(1),
          name.substring(0, name.length - 1),
          '$name ',
          ' $name',
          '${name}x',
          'darwin',
          'freebsd',
          'windows',
          '',
        ]),
        .string(alphabet: .lettersAndDigits),
      ]),
      label: 'system',
    );
    expect(Kernel.named(system), switch (system) {
      'macos' => Kernel.darwin,
      'linux' => Kernel.linux,
      _ => null,
    });
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

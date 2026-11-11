import 'dart:io';

import 'package:muster/src/model/os.dart';
import 'package:muster/src/store/process_environment.dart';
import 'package:test/test.dart';

void main() {
  test('the process\'s environment is read whole, with its system', () {
    final (:Map<String, String> variables, :Os os) = processEnvironment();
    expect(variables, Platform.environment);
    expect(os, Platform.isWindows ? Os.windows : Os.posix);
  });
}

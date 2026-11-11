import 'package:muster/src/store/store_fault.dart';
import 'package:test/test.dart';

/// Matches a [StoreFault] whose failure [failure] matches.
Matcher storeFault(Matcher failure) => isA<StoreFault>().having(
  (StoreFault fault) => fault.failure,
  'failure',
  failure,
);

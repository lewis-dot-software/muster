import 'package:muster/src/model/os.dart';
import 'package:muster/src/store/process_environment.dart';

/// The family of system the test process runs on.
final Os host = processEnvironment().os;

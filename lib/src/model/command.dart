import 'executable.dart';

/// A process muster starts: its `executable`, and the `arguments` it is
/// given, in order.
typedef Command = ({Executable executable, List<String> arguments});

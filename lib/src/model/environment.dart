import 'os.dart';

/// What muster reads of the process it runs in: its environment's
/// [variables], and the [os] it runs on.
typedef Environment = ({Map<String, String> variables, Os os});

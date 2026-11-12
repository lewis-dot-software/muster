import 'dart:io';

import 'package:path/path.dart' as p;

import 'shell_quoted.dart';

/// A program a test's caller names to answer a prompt, which writes each
/// prompt it is given to a file and answers none.
class Askpass {
  Askpass._(this.path, this._asked);

  /// The program made in `askpass` under [parent].
  static Future<Askpass> make(Directory parent) async {
    final String asked = p.join(parent.path, 'asked');
    final File program = await File(p.join(parent.path, 'askpass'))
        .writeAsString(
          '#!/bin/sh\nprintf "%s\\n" "\$1" >> ${shellQuoted(asked)}\nexit 1\n',
        );
    await Process.run('chmod', ['+x', program.path]);
    return ._(program.path, File(asked));
  }

  /// The program's path.
  final String path;

  final File _asked;

  /// Whether any prompt has reached the program.
  Future<bool> get asked => _asked.exists();
}

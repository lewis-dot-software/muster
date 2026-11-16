import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'loads.dart';
import 'probe_gone.dart';
import 'support_program.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await .systemTemp.createTemp('muster-');
  });

  tearDown(() => temp.delete(recursive: true));

  test('The gone probe starts from the kept kernel of its sources', () async {
    final String manifest = p.join(temp.path, 'empty.yaml');
    await writeManifest(manifest, []);
    final ProcessResult ran = await probeGone(temp, .fetch, manifest);
    expect(
      const LineSplitter().convert(ran.stderr as String).first,
      '${Uri.file(await SupportProgram.gone.kernel())}',
    );
  });
}

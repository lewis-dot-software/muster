import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muster/src/model/checkout_path.dart';
import 'package:muster/src/store/claims.dart';
import 'package:path/path.dart' as p;

/// The kernel of one program, compiled once for each state of what it is
/// compiled from and kept under a root, so every start of the program after
/// the first, from any isolate or process and in any later run, loads the
/// kept kernel.
class KernelCache {
  /// The kernel [checkout] names, `<checkout>-<key>.dill`, compiled by
  /// [compile] into the path it is given, from [sources], each a file or a
  /// directory whose every file it is compiled from, by the SDK whose version
  /// is [sdk], its claim held through [claims] while it is looked for and
  /// made.
  KernelCache({
    required this.checkout,
    required this.sources,
    required this.sdk,
    required this.compile,
    required this.claims,
  });

  /// The checkout whose path, with the key after it, names the kernel, and
  /// whose claim is held while the kernel is looked for and made, so no two
  /// isolates or processes make it at once.
  final CheckoutPath checkout;

  /// The files and directories the kernel is compiled from.
  final List<String> sources;

  /// The version of the SDK the kernel is compiled by, which loads no kernel
  /// another SDK compiled.
  final String sdk;

  /// Compiles the kernel into the file at the path it is given.
  final Future<void> Function(String output) compile;

  /// The claims the kernel's claim is held through.
  final Claims claims;

  /// The path of the kernel of [sources] as they stand, compiled where no
  /// kernel of them is kept, every kernel of an earlier state of them
  /// removed.
  ///
  /// Throws what [compile] throws, keeping nothing it wrote.
  Future<String> kernel() async {
    final String kernel = '${checkout.path}-${await _key()}.dill';
    return claims.holding(checkout.claim, () async {
      if (await File(kernel).exists()) {
        return kernel;
      }
      final File partial = .new('$kernel.partial');
      try {
        await compile(partial.path);
        await partial.rename(kernel);
      } finally {
        if (await partial.exists()) {
          await partial.delete();
        }
      }
      final String stale = '${p.basename(checkout.path)}-';
      await for (final FileSystemEntity entity in Directory(
        p.dirname(kernel),
      ).list()) {
        final String name = p.basename(entity.path);
        if (entity is File &&
            entity.path != kernel &&
            name.startsWith(stale) &&
            name.endsWith('.dill')) {
          await entity.delete();
        }
      }
      return kernel;
    });
  }

  /// A SHA-256, in hexadecimal, of [sdk] and each file of [sources], by its
  /// path under its source and its contents.
  Future<String> _key() async {
    final List<String> lines = [sdk];
    for (final (int index, String source) in sources.indexed) {
      final List<File> files = await FileSystemEntity.isDirectory(source)
          ? [
              await for (final FileSystemEntity entity in Directory(
                source,
              ).list(recursive: true))
                if (entity is File) entity,
            ]
          : [.new(source)];
      files.sort((File a, File b) => a.path.compareTo(b.path));
      for (final File file in files) {
        lines.add(
          '$index ${p.relative(file.path, from: source)} '
          '${sha256.convert(await file.readAsBytes())}',
        );
      }
    }
    return sha256.convert(utf8.encode(lines.join('\n'))).toString();
  }
}

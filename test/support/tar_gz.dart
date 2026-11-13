import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The gzipped ustar archive of [files], each path from the archive's top in
/// `/` separators, of at most 100 bytes, beside its contents, in the order
/// given.
List<int> tarGz(Map<String, String> files) {
  final BytesBuilder tar = .new(copy: false);
  for (final MapEntry<String, String>(key: path, value: text)
      in files.entries) {
    final List<int> contents = utf8.encode(text);
    tar
      ..add(_header(path, contents.length))
      ..add(contents)
      ..add(Uint8List(_padding(contents.length)));
  }
  // Two empty blocks end the archive.
  tar.add(Uint8List(_block * 2));
  return gzip.encode(tar.takeBytes());
}

const int _block = 512;

int _padding(int length) => (_block - length % _block) % _block;

/// The header block of a regular file at [path] holding [size] bytes.
Uint8List _header(String path, int size) {
  final List<int> name = utf8.encode(path);
  if (name.length > 100) {
    throw ArgumentError.value(path, 'path', 'longer than 100 bytes');
  }
  final Uint8List header = .new(_block)
    ..setAll(0, name)
    ..setAll(100, ascii.encode('0000644\x00'))
    ..setAll(108, ascii.encode('0000000\x00'))
    ..setAll(116, ascii.encode('0000000\x00'))
    ..setAll(124, ascii.encode('${size.toRadixString(8).padLeft(11, '0')}\x00'))
    ..setAll(136, ascii.encode('00000000000\x00'))
    // The checksum is summed with its own field read as spaces.
    ..setAll(148, ascii.encode('        '))
    ..[156] = 0x30
    ..setAll(257, ascii.encode('ustar\x00'))
    ..setAll(263, ascii.encode('00'));
  final int sum = header.fold(0, (int total, int byte) => total + byte);
  header.setAll(
    148,
    ascii.encode('${sum.toRadixString(8).padLeft(6, '0')}\x00 '),
  );
  return header;
}

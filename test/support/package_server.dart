import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

import 'tar_gz.dart';

/// A package server on the loopback that serves pub's hosted API for the
/// packages a test gives it, so pub fetches them with no network when
/// `PUB_HOSTED_URL` names [url].
class PackageServer {
  PackageServer._(this._server) {
    _server.listen(_answer);
  }

  /// The server, listening on a port of its own, serving no package yet.
  static Future<PackageServer> start() async =>
      ._(await .bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  /// Each package's versions, by name, each beside its files and the
  /// pubspec its listing gives.
  final Map<String, Map<String, _Served>> _packages = {};

  /// The server's URL, as `PUB_HOSTED_URL` names it.
  String get url => 'http://127.0.0.1:${_server.port}';

  /// Serves the package [name] at [version] with [files], each path from the
  /// package's top in `/` separators beside its contents, its pubspec among
  /// them, which the listing gives too. A [listed] pubspec is the listing's
  /// in its place, as a host gives that serves an archive with none.
  void serve(
    String name,
    String version,
    Map<String, String> files, {
    String? listed,
  }) {
    (_packages[name] ??= {})[version] = (
      files: files,
      pubspec: listed ?? files['pubspec.yaml']!,
    );
  }

  /// Stops the server.
  Future<void> close() => _server.close(force: true);

  Future<void> _answer(HttpRequest request) async {
    final HttpResponse response = request.response;
    switch (request.uri.pathSegments) {
      case ['api', 'packages', final String name]
          when _packages.containsKey(name):
        response.headers.contentType = .new('application', 'vnd.pub.v2+json');
        response.write(jsonEncode(_listing(name, _packages[name]!)));
      case ['packages', final String name, 'versions', final String archive]
          when _filesOf(name, archive) != null:
        response.add(tarGz(_filesOf(name, archive)!));
      default:
        response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  /// The listing pub reads of the package [name], whose [versions] are each
  /// beside its files.
  Map<String, Object?> _listing(String name, Map<String, _Served> versions) {
    final List<Map<String, Object?>> listed = [
      for (final MapEntry<String, _Served>(
            key: version,
            value: (:files, :pubspec),
          )
          in versions.entries)
        {
          'version': version,
          'pubspec': jsonDecode(jsonEncode(loadYaml(pubspec))),
          'archive_url': '$url/packages/$name/versions/$version$_archive',
          'archive_sha256': sha256.convert(tarGz(files)).toString(),
        },
    ];
    return {'name': name, 'latest': listed.last, 'versions': listed};
  }

  /// The files of the package [name]'s version that [archive] names, or
  /// null where none is served.
  Map<String, String>? _filesOf(String name, String archive) {
    if (!archive.endsWith(_archive)) {
      return null;
    }
    final String version = archive.substring(
      0,
      archive.length - _archive.length,
    );
    return _packages[name]?[version]?.files;
  }
}

/// A version served: the files of its archive, and the pubspec its listing
/// gives.
typedef _Served = ({Map<String, String> files, String pubspec});

const String _archive = '.tar.gz';

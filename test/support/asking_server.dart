import 'dart:io';

import 'package:muster/src/model/git_url.dart';

/// An HTTP server on the loopback that answers every request by asking for
/// credentials, so git's clone of it would prompt for them.
class AskingServer {
  AskingServer._(this._server);

  /// The server, listening on a port of its own.
  static Future<AskingServer> start() async {
    final HttpServer server = await .bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Basic realm="muster"',
        );
      await request.response.close();
    });
    return ._(server);
  }

  final HttpServer _server;

  /// A repo's URL on the server.
  GitUrl get url => .parse('http://127.0.0.1:${_server.port}/repo.git')!;

  /// Stops the server.
  Future<void> close() => _server.close(force: true);
}

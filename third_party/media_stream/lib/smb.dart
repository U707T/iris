import 'dart:async';
import 'package:media_stream/utils.dart';
import 'package:shelf/shelf.dart';
import 'package:smb_connect/smb_connect.dart';

class SmbConfig {
  final String host;
  final String domain;
  final String username;
  final String password;

  SmbConfig({
    required this.host,
    required this.domain,
    required this.username,
    required this.password,
  });
}

Future<Response> smbStream(Request request) async {
  final AuthCredentials? headerCredentials = parseBasicAuthHeader(request);

  final queryParams = request.url.queryParameters;
  final host = queryParams['host'];
  final domain = queryParams['domain'];
  final username = headerCredentials?.username ?? queryParams['username'];
  final password = headerCredentials?.password ?? queryParams['password'];
  final path = queryParams['path'];

  if (host == null || username == null || password == null || path == null) {
    return Response.badRequest(body: 'Missing required parameters');
  }

  final config = SmbConfig(
    host: host,
    domain: domain ?? '',
    username: username,
    password: password,
  );

  final connect = await SmbConnect.connectAuth(
    host: config.host,
    domain: config.domain,
    username: config.username,
    password: config.password,
    debugPrint: false,
    debugPrintLowLevel: false,
  );

  SmbFile file = await connect.file(path);

  int fileSize = file.size;

  final [start, end, contentLength] = getRange(request, fileSize);

  final fileStream = await connect.openRead(file, start, end + 1);

  final headers = getHeaders(fileSize, start, end, contentLength);

  return Response(206, headers: headers, body: fileStream);
}

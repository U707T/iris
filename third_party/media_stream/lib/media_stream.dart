import 'dart:async';
import 'dart:io';
import 'package:media_stream/ftp.dart';
import 'package:media_stream/smb.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

class MediaStream {
  static final MediaStream _instance = MediaStream._internal(
    host: 'localhost',
    port: 8760,
  );

  factory MediaStream() {
    return _instance;
  }

  HttpServer? _server;
  final String host;
  int port;

  MediaStream._internal({this.host = 'localhost', this.port = 8760});

  /// 端口被占用时最多向上尝试的端口数
  static const int _maxPortAttempts = 20;

  Future<void> startServer() async {
    if (_server != null) {
      print('Server is already running at $url');
      return;
    }

    final router = Router();
    router.get('/ftp', _handleFtpStreamRequest);
    router.get('/smb', _handleSmbStreamRequest);
    final handler = const Pipeline().addHandler(router.call);

    Object? lastError;
    for (var attempt = 0; attempt < _maxPortAttempts; attempt++) {
      try {
        _server = await io.serve(handler, host, port);
        print('Streaming server started successfully at $url');
        return;
      } on SocketException catch (e) {
        lastError = e;
        final code = e.osError?.errorCode;
        if (code == 10048 || code == 48 || code == 98) {
          print('Port $port is in use, trying port ${port + 1}...');
          port++;
          continue;
        }
        print('An unexpected network error occurred: $e');
        break;
      } catch (e) {
        lastError = e;
        print('An unexpected error occurred during server startup: $e');
        break;
      }
    }

    // 旧实现是 while (true): 绑定持续失败时永远不会返回, await 它会卡住整个启动。
    throw StateError('Failed to start streaming server: $lastError');
  }

  Future stopServer() async {
    await _server?.close();
    _server = null;
    print('Streaming server stopped');
  }

  String? get url {
    if (_server != null) {
      return 'http://${_server!.address.host}:${_server!.port}';
    }
    return null;
  }

  Future<Response> _handleFtpStreamRequest(Request request) async {
    try {
      return await ftpStream(request);
    } catch (e) {
      print('Request processing error: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  Future<Response> _handleSmbStreamRequest(Request request) async {
    try {
      return await smbStream(request);
    } catch (e) {
      print('Request processing error: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }
}

import 'dart:async';
import 'dart:math';
import 'package:media_stream/utils.dart';
import 'package:pure_ftp/pure_ftp.dart';
import 'package:shelf/shelf.dart';

class FtpConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final String? account;
  FtpConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.account,
  });
}

Future<Response> ftpStream(Request request) async {
  final AuthCredentials? headerCredentials = parseBasicAuthHeader(request);

  final queryParams = request.url.queryParameters;
  final host = queryParams['host'];
  final port = int.parse(queryParams['port'] ?? '21');
  final username = headerCredentials?.username ?? queryParams['username'];
  final password = headerCredentials?.password ?? queryParams['password'];
  final account = queryParams['account'];
  final path = queryParams['path'];

  if (host == null || path == null) {
    return Response.badRequest(body: 'Missing required parameters');
  }

  final config = FtpConfig(
    host: host,
    port: port,
    username: username ?? 'anonymous',
    password: password ?? '',
    account: account,
  );

  final client = FtpClient(
    socketInitOptions: FtpSocketInitOptions(
      host: config.host,
      port: config.port,
    ),
    authOptions: FtpAuthOptions(
      username: config.username,
      password: config.password,
      account: config.account,
    ),
    logCallback: null,
  );

  try {
    await client.connect();

    final file = client.getFile(path);
    final fileSize = await file.size();

    if (fileSize <= 0) {
      await client.disconnect();
      print('File not found or empty');

      return Response.notFound('File not found or empty');
    }

    final [start, end, contentLength] = getRange(request, fileSize);

    if (start >= fileSize || contentLength <= 0) {
      return Response(416, body: 'Range Not Satisfiable');
    }

    final fileStream = _downloadFileStream(client, file, start, end);

    final headers = getHeaders(fileSize, start, end, contentLength);

    return Response(206, body: fileStream, headers: headers);
  } catch (e) {
    print('Error during FTP processing: $e');
    if (await client.isConnected()) {
      await client.disconnect();
    }
    return Response.internalServerError(body: 'Error: $e');
  }
}

Stream<List> _downloadFileStream(
  FtpClient client,
  FtpFile file,
  int start,
  int end,
) {
  final contentLength = end - start + 1;

  final controller = StreamController<List>();
  var transferred = 0;
  close() async {
    print('Stream closed');
    FtpCommand.ABOR.write(client.socket);
    await client.disconnect();
    await controller.close();
  }

  controller.onListen = () async {
    try {
      final socket = client.socket;
      await socket.openTransferChannel((socketFuture, log) async {
        await FtpCommand.TYPE.writeAndRead(socket, [
          FtpTransferType.binary.type,
        ]);
        if (start > 0) {
          final ret = await FtpCommand.REST.writeAndRead(socket, ['$start']);
          if (ret.code >= 400) {
            throw FtpException('Failed to set REST point: ${ret.message}');
          }
        }
        FtpCommand.RETR.write(socket, [file.path]);
        final dataSocket = await socketFuture;
        final response = await socket.read();

        if (!response.isSuccessfulForDataTransfer) {
          throw FtpException(
            'Error while downloading file: ${response.message}',
          );
        }

        await dataSocket.listenAsync((chunk) async {
          final bytesRemaining = contentLength - transferred;
          final bytesToSend = min(chunk.length, bytesRemaining);

          controller.add(chunk.sublist(0, bytesToSend));
          transferred += bytesToSend;

          if (transferred >= contentLength) {
            await dataSocket.close(ClientSocketDirection.readWrite);
          }
        });

        await close();
      });
    } catch (e) {
      close();
    }
  };
  return controller.stream;
}

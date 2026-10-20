import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';

int getDynamicChunkSize(int fileSizeInBytes) {
  const int megabyte = 1024 * 1024;

  final int calculatedChunkSize = (fileSizeInBytes * 0.01).round();
  const int minChunkSize = 2 * megabyte;
  const int maxChunkSize = 25 * megabyte;

  if (fileSizeInBytes < 10 * megabyte) {
    return fileSizeInBytes;
  }

  return calculatedChunkSize.clamp(minChunkSize, maxChunkSize);
}

getRange(request, fileSize) {
  final chunkSize = getDynamicChunkSize(fileSize);

  int start = 0;

  final rangeHeader = request.headers['range'];
  if (rangeHeader != null) {
    final range = rangeHeader.substring('bytes='.length).split('-');
    start = int.tryParse(range[0]) ?? 0;
  }

  final end = min(start + chunkSize, fileSize) - 1;

  final contentLength = end - start + 1;

  print('start: $start, end: $end, contentLength: $contentLength');

  return [start, end, contentLength];
}

getHeaders(fileSize, start, end, contentLength) {
  final headers = {
    'Content-Type': 'application/octet-stream',
    'Content-Length': contentLength.toString(),
    'Accept-Ranges': 'bytes',
  };

  if (start == 0 && end == fileSize - 1) {
    headers['Content-Disposition'] = 'attachment; filename="file"';
  } else {
    headers['Content-Range'] = 'bytes $start-$end/$fileSize';
    headers['Content-Disposition'] = 'attachment; filename="file"';
    headers['Content-Length'] = contentLength.toString();
  }

  return headers;
}

class AuthCredentials {
  final String username;
  final String password;
  AuthCredentials({required this.username, required this.password});
}

AuthCredentials? parseBasicAuthHeader(Request request) {
  final authHeader =
      request.headers['Authorization'] ?? request.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Basic ')) {
    return null;
  }

  try {
    final String encodedCredentials = authHeader.substring('Basic '.length);
    final String decoded = utf8.decode(base64.decode(encodedCredentials));

    final List<String> parts = decoded.split(':');
    if (parts.length == 2) {
      return AuthCredentials(username: parts[0], password: parts[1]);
    }
  } catch (e) {
    print('parseBasicAuthHeader error: $e');
  }
  return null;
}

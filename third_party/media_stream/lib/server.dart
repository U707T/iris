import 'package:media_stream/media_stream.dart';

void main() async {
  MediaStream mediaStream = MediaStream();

  await mediaStream.startServer();
}

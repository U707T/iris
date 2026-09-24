import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:iris/utils/logger.dart';

/// 将 RGBA 原始像素数据编码为 PNG (在后台 isolate 中执行, 避免大图卡顿)。
///
/// FVP 的 `snapshot()` 返回的是 `width * height * 4` 字节的 RGBA 数据。
/// 返回 null 表示编码失败。
Future<Uint8List?> encodeRgbaToPng(
  Uint8List rgba, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) return Future.value(null);
  if (rgba.length < width * height * 4) return Future.value(null);
  return compute(_encodeRgbaToPng, [rgba, width, height]);
}

Uint8List? _encodeRgbaToPng(List<Object> args) {
  final rgba = args[0] as Uint8List;
  final width = args[1] as int;
  final height = args[2] as int;

  try {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  } catch (e) {
    logger('Error encoding screenshot: $e');
    return null;
  }
}

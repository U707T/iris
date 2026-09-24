import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:iris/utils/logger.dart';

/// 将 RGBA 原始像素数据编码为 PNG。
///
/// FVP 的 `snapshot()` 返回的是 `width * height * 4` 字节的 RGBA 数据。
/// 返回 null 表示编码失败。
Uint8List? encodeRgbaToPng(
  Uint8List rgba, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) return null;
  if (rgba.length < width * height * 4) return null;

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

import 'package:media_kit/media_kit.dart';

/// setProperty in media_kit 1.2.6 discards mpv's status code. Read the option back
/// before allowing a network source, rather than assuming the call succeeded.
Future<void> verifyNativePlaybackTls({
  required Future<void> Function(String, String) setProperty,
  required Future<String> Function(String) getProperty,
  required bool networkSource,
}) async {
  try {
    await setProperty('tls-verify', 'yes').timeout(const Duration(seconds: 5));
    final value = (await getProperty(
      'tls-verify',
    ).timeout(const Duration(seconds: 5))).trim().toLowerCase();
    if (networkSource && !const {'yes', 'true', '1'}.contains(value)) {
      throw StateError('The native player could not enable TLS verification');
    }
  } catch (_) {
    if (networkSource) rethrow;
  }
}

Future<void> ensurePlaybackTls(Player player, String mediaUri) async {
  final native = player.platform;
  if (native is! NativePlayer) return;
  final scheme = Uri.tryParse(mediaUri)?.scheme.toLowerCase() ?? '';
  // One-character schemes are Windows drive letters.
  final networkSource =
      scheme.length > 1 && !const {'file', 'fd', 'content'}.contains(scheme);
  await verifyNativePlaybackTls(
    setProperty: (name, value) => native.setProperty(name, value),
    getProperty: (name) => native.getProperty(name),
    networkSource: networkSource,
  );
}

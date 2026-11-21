import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/player/playback_tls.dart';
import 'package:media_kit/media_kit.dart';

class _Native extends Fake implements NativePlayer {
  _Native(this.value);
  final String value;
  final calls = <String>[];
  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    expect(waitForInitialization, isTrue);
    calls.add('set:$property=$value');
  }

  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    expect(waitForInitialization, isTrue);
    calls.add('get:$property');
    return value;
  }
}

class _Player extends Fake implements Player {
  _Player(this.native);
  final NativePlayer native;
  @override
  NativePlayer get platform => native;
}

void main() {
  test(
    'native network playback sets TLS verification and checks it back',
    () async {
      final native = _Native('yes');
      await ensurePlaybackTls(_Player(native), 'https://example.test/a.mp4');
      expect(native.calls, ['set:tls-verify=yes', 'get:tls-verify']);
    },
  );
  test(
    'unsupported native TLS option fails closed for network sources',
    () async {
      for (final value in ['no', '', 'unknown']) {
        final native = _Native(value);
        await expectLater(
          ensurePlaybackTls(_Player(native), 'https://example.test/a.mp4'),
          throwsStateError,
        );
      }
    },
  );
  test(
    'local media remains playable when native TLS option is unavailable',
    () async {
      final native = _Native('');
      await ensurePlaybackTls(_Player(native), r'C:\media\a.mp4');
      expect(native.calls.length, 2);
    },
  );
}

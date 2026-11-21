import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/player/use_player_stats.dart';
import 'package:media_kit/media_kit.dart';

class _NativePlayer extends Fake implements NativePlayer {
  int reads = 0;

  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async => '${++reads}';
}

class _Player extends Fake implements Player {
  _Player(this.backend);
  final _NativePlayer backend;

  @override
  NativePlayer get platform => backend;
}

void main() {
  testWidgets('stats polling starts after toggle, stops and restarts', (
    tester,
  ) async {
    final shown = ValueNotifier(false);
    final backend = _NativePlayer();
    final player = _Player(backend);
    Map<String, String> Function()? readStats;
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (_, visible, _) => HookBuilder(
          builder: (_) {
            readStats = usePlayerStats(player, isShowStats: visible);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(backend.reads, 0);

    shown.value = true;
    await tester.pump();
    await tester.idle();
    expect(backend.reads, 5);
    final first = Map<String, String>.of(readStats!());
    await tester.pump(const Duration(seconds: 1));
    await tester.idle();
    expect(backend.reads, 10);
    expect(readStats!(), isNot(equals(first)));
    await tester.pump(const Duration(seconds: 1));
    await tester.idle();
    expect(backend.reads, 15);

    shown.value = false;
    await tester.pump();
    final stoppedReads = backend.reads;
    await tester.pump(const Duration(seconds: 2));
    await tester.idle();
    expect(backend.reads, stoppedReads);

    shown.value = true;
    await tester.pump();
    await tester.idle();
    expect(backend.reads, stoppedReads + 5);
    await tester.pump(const Duration(seconds: 1));
    await tester.idle();
    expect(backend.reads, stoppedReads + 10);

    await tester.pumpWidget(const SizedBox.shrink());
    final disposedReads = backend.reads;
    await tester.pump(const Duration(seconds: 2));
    expect(backend.reads, disposedReads);
    shown.dispose();
  });
}

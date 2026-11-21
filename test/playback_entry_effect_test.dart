import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/player/playback_load_session.dart';
import 'package:iris/models/file.dart';

void main() {
  testWidgets(
    'equal FileItems in different queue entries reload, stop and unmount invalidate',
    (tester) async {
      const file = FileItem(name: 'same.mp4', uri: '/same.mp4');
      var loads = 0;
      var stops = 0;
      var invalidations = 0;
      final entry = ValueNotifier<int>(0);
      await tester.pumpWidget(
        ValueListenableBuilder<int>(
          valueListenable: entry,
          builder: (_, index, _) => HookBuilder(
            builder: (_) {
              usePlaybackEntryEffect(
                file: index < 0 ? null : file,
                entryIndex: index,
                load: () {
                  loads++;
                },
                stop: () {
                  stops++;
                },
                invalidate: () {
                  invalidations++;
                },
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(loads, 1);
      entry.value = 1;
      await tester.pump();
      expect(
        loads,
        2,
        reason: 'same media in another queue entry is a new load',
      );
      expect(invalidations, 1);
      entry.value = -1;
      await tester.pump();
      expect(stops, 1);
      expect(invalidations, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(invalidations, 4);
      entry.dispose();
    },
  );
}

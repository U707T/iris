import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/pages/player/gesture/player_drag_recognizer.dart';

void main() {
  testWidgets(
    'rejecting extra pointers preserves primary drag; primary rejection cancels once',
    (tester) async {
      var starts = 0;
      var updates = 0;
      var cancels = 0;
      var ends = 0;
      late PlayerDragGestureRecognizer recognizer;
      final delegate = PlayerDragDelegate()
        ..screenWidth = 600
        ..onStart = (_, _) {
          starts++;
        }
        ..onUpdate = (_, _) {
          updates++;
        }
        ..onCancel = (_) {
          cancels++;
        }
        ..onEnd = (_) {
          ends++;
        };
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    () => TapGestureRecognizer()..onTap = () {},
                    (_) {},
                  ),
              PlayerDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    PlayerDragGestureRecognizer
                  >(
                    () => recognizer = PlayerDragGestureRecognizer(
                      delegate: delegate,
                    ),
                    (_) {},
                  ),
            },
            child: const SizedBox.expand(),
          ),
        ),
      );
      final first = await tester.startGesture(
        const Offset(300, 400),
        pointer: 1,
      );
      await first.moveBy(const Offset(40, 0));
      expect(starts, 1);
      final beforeExtra = updates;
      final second = await tester.startGesture(
        const Offset(400, 400),
        pointer: 2,
      );
      await second.up();
      await first.moveBy(const Offset(20, 0));
      expect(updates, greaterThan(beforeExtra));
      expect(cancels, 0);
      recognizer.rejectGesture(1);
      expect(cancels, 1);
      await first.up();
      expect(cancels, 1);
      expect(ends, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

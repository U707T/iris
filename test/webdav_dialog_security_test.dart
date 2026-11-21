import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/widgets/dialogs/show_webdav_dialog.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(WebDAVDialog dialog) => StoreScope(
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: dialog)),
  ),
);

void main() {
  testWidgets(
    'new connections use HTTPS, HTTP cannot test before acknowledgement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final attempts = <WebDAVStorage>[];
      await tester.pumpWidget(
        _app(
          WebDAVDialog(
            connectionTester: (storage) async {
              attempts.add(storage);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Test connection'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(attempts, isEmpty);
      await tester.enterText(
        find.byType(TextFormField).last,
        ' secret with space ',
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Test connection'));
      await tester.pumpAndSettle();
      expect(attempts.single.https, false);
      expect(attempts.single.password, ' secret with space ');
    },
  );
}

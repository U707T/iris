import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/info.dart';
import 'package:iris/l10n/app_localizations.dart';
import 'package:iris/models/file.dart';
import 'package:iris/pages/home/home.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/theme.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/request_storage_permission.dart';
import 'package:iris/utils/windows_a11y_compat.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_stream/media_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saf_util/saf_util.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'globals.dart' as globals;

void main(List<String> arguments) async {
  logger('arguments: $arguments');
  // 兼容开关自身不能当作文档路径传给播放队列 (use_play_queue_store 会取 arguments[0])
  globals.arguments = List<String>.from(arguments)
    ..removeWhere((argument) => argument == kDisableWindowsA11yArgument);
  globals.disableWindowsA11y = shouldDisableWindowsA11y(
    isWindows: Platform.isWindows,
    environment: Platform.environment,
    arguments: arguments,
  );
  if (globals.disableWindowsA11y) {
    logger(
      'Windows accessibility disabled by compat flag '
      '(engine crash workaround, flutter/flutter#175041)',
    );
  }

  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();

  fvp.registerWith(options: {
    // 'fastSeek': true,
    'player': {
      if (Platform.isAndroid) 'audio.renderer': 'AudioTrack',
      'avio.reconnect': '1',
      'avio.reconnect_delay_max': '7',
      'buffer': '2000+80000',
      'demux.buffer.ranges': '8',
    },
    if (Platform.isAndroid)
      'subtitleFontFile': 'assets/fonts/NotoSansCJKsc-Medium.otf',
    // 仅在调试构建中开启详细日志, 减少 release 版性能开销
    'global': {'log': kDebugMode ? 'debug' : 'off'},
  });

  final appLinks = AppLinks();
  final initUri = await appLinks.getInitialLinkString();

  if (initUri != null) {
    logger('initUri: $initUri');
    globals.initUri = initUri;
  }

  if (isDesktop) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(427, 240),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  MediaStream mediaStream = MediaStream();
  mediaStream.startServer();

  runApp(const StoreScope(child: MyApp()));
}

class MyApp extends HookWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      () async {
        globals.storagePermissionStatus = Platform.isAndroid
            ? await isAndroid11OrHigher()
                ? await Permission.manageExternalStorage.status
                : await Permission.storage.status
            : PermissionStatus.granted;
      }();
      return null;
    }, []);

    ThemeMode themeMode =
        useAppStore().select(context, (state) => state.themeMode);
    String language = useAppStore().select(context, (state) => state.language);
    bool pureBlackTheme =
        useAppStore().select(context, (state) => state.pureBlackTheme);

    final appLinks = useMemoized(() => AppLinks());
    final String? uri = useStream(appLinks.stringLinkStream).data;

    useEffect(() {
      () async {
        if (uri != null && globals.initUri != uri) {
          logger('Uri: $uri');
          if (Platform.isAndroid) {
            final file = await SafUtil().documentFileFromUri(uri, false);
            if (file != null) {
              await useAppStore().updateAutoPlay(true);
              await usePlayQueueStore().update(
                playQueue: [
                  PlayQueueItem(
                    file: FileItem(
                      name: file.name,
                      uri: file.uri,
                      size: file.length,
                    ),
                    index: 0,
                  ),
                ],
                index: 0,
              );
            }
          }
        }
      }();
      return null;
    }, [uri]);

    return DynamicColorBuilder(builder: (
      ColorScheme? lightDynamic,
      ColorScheme? darkDynamic,
    ) {
      final theme = getTheme(
        context: context,
        lightDynamic: lightDynamic,
        darkDynamic: darkDynamic,
        pureBlack: pureBlackTheme,
      );

      return MaterialApp(
        title: INFO.title,
        theme: theme.light,
        darkTheme: theme.dark,
        themeMode: themeMode,
        home: const Home(),
        builder: (context, child) {
          // 兼容尚未迁移到 material_ui 的第三方包 (popover / flutter_markdown 等)
          // ignore: deprecated_member_use
          final Widget content = MaterialUiCompatibilityBridge(child: child!);
          // 临时规避 Windows 引擎无障碍桥崩溃 (flutter/flutter#175041):
          // 开启后关闭本应用的 Windows 无障碍集成, 引擎便不再构建语义树。
          // 代价: 屏幕阅读器无法读取本应用。详见 windows_a11y_compat.dart。
          return maybeExcludeSemantics(
            child: content,
            disabled: globals.disableWindowsA11y,
          );
        },
        locale: language == 'system' || language == 'auto'
            ? null
            : Locale(language),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        localeResolutionCallback: (locale, supportedLocales) => supportedLocales
                .map((e) => e.languageCode)
                .toList()
                .contains(locale!.languageCode)
            ? null
            : const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
      );
    });
  }
}

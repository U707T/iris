import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
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
    ..removeWhere((argument) =>
        argument == kDisableWindowsA11yArgument ||
        argument == kEnableWindowsA11yArgument);
  globals.disableWindowsA11y = shouldDisableWindowsA11y(
    isWindows: Platform.isWindows,
    environment: Platform.environment,
    arguments: arguments,
  );
  if (Platform.isWindows) {
    logger(
      globals.disableWindowsA11y
          ? 'Windows accessibility disabled by default compat mode '
              '(engine crash workaround, flutter/flutter#175041; '
              'set IRIS_ENABLE_WINDOWS_A11Y=1 to opt out)'
          : 'Windows accessibility enabled by opt-out flag '
              '(engine crash workaround off, flutter/flutter#175041)',
    );
  }

  WidgetsFlutterBinding.ensureInitialized();

  // 全局兜底: 未捕获的异常至少要进日志, 并把 release 版的红屏 / 灰屏
  // 换成一个可读的提示 (单个组件出错不再让整个画面变成色块)。
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger('Flutter error: ${details.exceptionAsString()}\n${details.stack}');
  };
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger('Uncaught error: $error\n$stack');
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => _UnexpectedErrorView(details: details);
  }

  MediaKit.ensureInitialized();

  try {
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
  } catch (e) {
    // FVP 后端注册失败不应阻止应用启动 (Media Kit 后端仍可用)
    logger('Failed to register FVP backend: $e');
  }

  // 冷启动的 "打开方式" 链接: 失败 / 插件不回调时照常启动, 不能卡在启动页
  final initUri = await _startupStep(
    AppLinks().getInitialLinkString(),
    const Duration(seconds: 3),
    'initial link',
  );

  if (initUri != null) {
    logger('initUri: $initUri');
    globals.initUri = initUri;
  }

  if (isDesktop) {
    try {
      await windowManager
          .ensureInitialized()
          .timeout(const Duration(seconds: 3));

      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 720),
        minimumSize: Size(427, 240),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );

      unawaited(
        windowManager
            .waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          await windowManager.focus();
        })
            .catchError((Object e) {
          logger('Failed to show window: $e');
        }),
      );
    } catch (e) {
      logger('Failed to initialize window manager: $e');
    }
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const StoreScope(child: MyApp()));

  // FTP / SMB 串流服务只用于网络播放。必须放在 runApp 之后:
  // media_stream 的 startServer() 内部是 `while (true)` 的重试循环,
  // 绑定失败 (端口被占 / 防火墙 / IPv6 不可用) 时永远不返回。
  // v2.4.0 把它 await 在 runApp 之前, 首帧因此一直出不来 —— 表现就是黑屏。
  unawaited(_startMediaStreamServer());
}

/// 启动阶段的异步步骤统一加超时: 插件不回调时宁可降级, 也不能卡住首帧。
Future<String?> _startupStep(
  Future<String?> future,
  Duration timeout,
  String label,
) async {
  try {
    return await future.timeout(timeout);
  } catch (e) {
    logger('Startup step "$label" failed: $e');
    return null;
  }
}

/// 启动串流服务 (失败只影响 FTP / SMB 播放, 不影响本地与直链)。
Future<void> _startMediaStreamServer() async {
  try {
    final mediaStream = MediaStream();
    // 再兜一层超时: 循环本身不会结束, 但这里不能拖住其他初始化
    await mediaStream.startServer().timeout(const Duration(seconds: 15));
    logger('MediaStream server: ${mediaStream.url}');
  } on TimeoutException {
    logger('MediaStream server did not start within 15s');
  } catch (e) {
    logger('Failed to start MediaStream server: $e');
  }
}

class MyApp extends HookWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      () async {
        try {
          globals.storagePermissionStatus = Platform.isAndroid
              ? await isAndroid11OrHigher()
                  ? await Permission.manageExternalStorage.status
                  : await Permission.storage.status
              : PermissionStatus.granted;
        } catch (e) {
          logger('Failed to read storage permission status: $e');
        }
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
            try {
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
            } catch (e) {
              logger('Failed to open URI: $e');
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
        localeResolutionCallback: (locale, supportedLocales) {
          if (locale == null) return const Locale('en');
          return supportedLocales
                  .map((e) => e.languageCode)
                  .toList()
                  .contains(locale.languageCode)
              ? null
              : const Locale('en');
        },
        supportedLocales: AppLocalizations.supportedLocales,
      );
    });
  }
}

/// release 构建下的兜底错误界面。
///
/// Flutter 默认在 release 里只画一个灰色方块, 用户看不出发生了什么。
/// 这里给一个可读的提示 (不依赖 Material / 本地化, 组件树出问题时也能画出来)。
class _UnexpectedErrorView extends StatelessWidget {
  const _UnexpectedErrorView({this.details});

  /// 出错的组件信息 (release 下也能给出一点线索, 便于用户反馈)
  final FlutterErrorDetails? details;

  @override
  Widget build(BuildContext context) {
    final message = details?.exceptionAsString() ?? '';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF161618),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 44,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 12),
                const Text(
                  '界面出现异常 / Something went wrong',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      height: 1.4,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

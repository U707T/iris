import 'package:flutter_test/flutter_test.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/picture_in_picture.dart';
import 'package:material_ui/material_ui.dart';

/// 画中画的"规则层": 谁能进、进去多大、宽高比怎么夹。
///
/// 平台侧 (Android `PictureInPictureParams` / 桌面窗口) 本地都没法真跑, 所以
/// 这里守住三件能算的事:
///
/// - 宽高比先夹到系统接受的区间, 否则 Android 会抛 `IllegalArgumentException`
///   而用户看到的是"点了没反应";
/// - 只有真在放视频时才允许系统在按 Home 时自动进小窗 —— 暂停 / 音频 /
///   短视频 / 播放失败都不该留一个冻住的小窗在桌面上;
/// - 桌面小窗的尺寸永远落在工作区里, 竖屏视频也不会长到屏幕外。
void main() {
  group('宽高比夹取', () {
    test('正常比例原样返回', () {
      expect(resolvePictureInPictureAspect(16 / 9), closeTo(16 / 9, 1e-9));
      expect(resolvePictureInPictureAspect(9 / 16), closeTo(9 / 16, 1e-9));
      expect(resolvePictureInPictureAspect(1.0), 1.0);
    });

    test('超宽 / 过窄收到系统区间', () {
      // 2.4:1 的宽银幕就已经越过 Android 的 2.39 上限
      expect(
        resolvePictureInPictureAspect(2.4),
        maxPictureInPictureAspect,
      );
      expect(
        resolvePictureInPictureAspect(3.0),
        maxPictureInPictureAspect,
      );
      expect(
        resolvePictureInPictureAspect(0.2),
        minPictureInPictureAspect,
      );
    });

    test('未知 / 非法比例退回 16:9', () {
      for (final double? ratio in <double?>[null, 0, -1, double.nan, double.infinity]) {
        expect(
          resolvePictureInPictureAspect(ratio),
          closeTo(fallbackPictureInPictureAspect, 1e-9),
          reason: '$ratio 不是可用的宽高比',
        );
      }
    });
  });

  group('自动进入的条件', () {
    bool arm({
      bool enabled = true,
      bool supported = true,
      bool isVideo = true,
      bool isPlaying = true,
      bool isShortVideoMode = false,
      bool hasError = false,
      bool hasOverlay = false,
    }) =>
        shouldArmAutoPictureInPicture(
          enabled: enabled,
          supported: supported,
          isVideo: isVideo,
          isPlaying: isPlaying,
          isShortVideoMode: isShortVideoMode,
          hasError: hasError,
          hasOverlay: hasOverlay,
        );

    test('开关开着 + 正在放视频 = 允许', () {
      expect(arm(), isTrue);
    });

    test('任何一项不满足都解除', () {
      expect(arm(enabled: false), isFalse, reason: '设置里关掉了画中画');
      expect(arm(supported: false), isFalse, reason: '设备不支持 PiP');
      expect(arm(isVideo: false), isFalse, reason: '音频没有画面可看');
      expect(arm(isPlaying: false), isFalse, reason: '暂停时进小窗只有冻住的画面');
      expect(arm(isShortVideoMode: true), isFalse, reason: '短视频模式有自己的播放器池');
      expect(arm(hasError: true), isFalse, reason: '播放失败时别把错误提示缩小成小窗');
      expect(arm(hasOverlay: true), isFalse,
          reason: '设置 / 播放队列开着时不该把小窗变成缩小版设置页');
    });
  });

  group('桌面小窗的尺寸与位置', () {
    const Rect desktop = Rect.fromLTWH(0, 0, 1920, 1040);

    test('16:9 贴右下角, 宽度取默认值', () {
      final bounds = computePictureInPictureBounds(
        workArea: desktop,
        aspectRatio: 16 / 9,
      );

      expect(bounds.width, pictureInPictureWindowWidth);
      expect(bounds.height, closeTo(420 / (16 / 9), 1e-9));
      expect(
        bounds.right,
        closeTo(desktop.right - pictureInPictureWindowMargin, 1e-9),
      );
      expect(
        bounds.bottom,
        closeTo(desktop.bottom - pictureInPictureWindowMargin, 1e-9),
      );
    });

    test('竖屏视频按高度收进工作区', () {
      final bounds = computePictureInPictureBounds(
        workArea: desktop,
        aspectRatio: 9 / 16,
      );

      expect(bounds.height, lessThanOrEqualTo(desktop.height));
      expect(bounds.width / bounds.height, closeTo(9 / 16, 1e-9));
      expect(bounds.left, greaterThanOrEqualTo(desktop.left));
      expect(bounds.top, greaterThanOrEqualTo(desktop.top));
    });

    test('超宽比例先夹再算, 不会变成一条线', () {
      final bounds = computePictureInPictureBounds(
        workArea: desktop,
        aspectRatio: 5.0,
      );

      expect(
        bounds.width / bounds.height,
        closeTo(maxPictureInPictureAspect, 1e-9),
      );
      expect(bounds.height, greaterThan(100));
    });

    test('小屏幕上整体缩进工作区', () {
      const Rect small = Rect.fromLTWH(0, 0, 320, 200);

      final bounds = computePictureInPictureBounds(
        workArea: small,
        aspectRatio: 16 / 9,
      );

      expect(bounds.width, lessThanOrEqualTo(320));
      expect(bounds.height, lessThanOrEqualTo(200));
      expect(small.contains(bounds.topLeft), isTrue);
      expect(bounds.right, lessThanOrEqualTo(small.right));
      expect(bounds.bottom, lessThanOrEqualTo(small.bottom));
    });

    test('任何比例都落在工作区里', () {
      for (final double ratio in <double>[0.2, 0.5, 9 / 16, 1, 16 / 9, 2.35, 4]) {
        for (final Rect area in <Rect>[
          desktop,
          const Rect.fromLTWH(100, 40, 1280, 720),
          const Rect.fromLTWH(-1280, 0, 1280, 720), // 左侧副屏
        ]) {
          final bounds = computePictureInPictureBounds(
            workArea: area,
            aspectRatio: ratio,
          );

          expect(bounds.left, greaterThanOrEqualTo(area.left));
          expect(bounds.top, greaterThanOrEqualTo(area.top));
          expect(bounds.right, lessThanOrEqualTo(area.right + 1e-9));
          expect(bounds.bottom, lessThanOrEqualTo(area.bottom + 1e-9));
        }
      }
    });
  });

  group('状态', () {
    test('PlayerUiStore 镜像小窗状态', () {
      final store = usePlayerUiStore();
      store.updatePictureInPicture(true);
      expect(store.state.isPictureInPicture, isTrue);
      store.updatePictureInPicture(false);
      expect(store.state.isPictureInPicture, isFalse);
    });

    test('AppState 默认关闭, 旧配置文件缺字段也能读', () {
      expect(const AppState().pictureInPicture, isFalse);
      expect(AppState.fromJson(const <String, dynamic>{}).pictureInPicture,
          isFalse);
      expect(
        AppState.fromJson(const <String, dynamic>{'pictureInPicture': true})
            .pictureInPicture,
        isTrue,
      );
    });

    test('开关会写进持久化 JSON', () {
      expect(
        const AppState(pictureInPicture: true).toJson()['pictureInPicture'],
        isTrue,
      );
    });

    test('能力探测结果就是设置页 / 菜单的可见性来源', () {
      globals.pictureInPictureSupported = true;
      expect(PictureInPicture.isSupported, isTrue);

      globals.pictureInPictureSupported = false;
      expect(PictureInPicture.isSupported, isFalse);
    });
  });
}

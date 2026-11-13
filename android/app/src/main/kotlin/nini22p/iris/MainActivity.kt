package nini22p.iris

import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /**
     * 画中画通道。Dart 侧的实现见 lib/utils/picture_in_picture.dart。
     *
     * Flutter 只负责"什么时候该进"(设置开关 + 当前是不是在放视频)，
     * 真正的小窗归系统管: 这里只把参数转成 PictureInPictureParams，并把
     * 系统进出小窗的事件回给 Dart。
     */
    private var pictureInPictureChannel: MethodChannel? = null

    /** 用户按 Home / 上滑离开时要不要自动进小窗。由 Dart 按播放条件设置。 */
    private var autoEnterPictureInPicture = false

    /** 最近一次的宽高比。手动、自动、系统接管三条路径都用这一份。 */
    private var pictureInPictureAspectRatio = 16.0 / 9.0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 全面屏: 允许内容延伸到刘海 / 挖孔区域。
        // 顶部控件在 Flutter 侧用 MediaQuery.viewPadding.top 让位, 视频画面保持居中。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // WebDAV 对话框的"读取默认网关"按钮。
        // Android 10+ 不再允许普通应用读 /proc/net/route, 执行 ip route 也常被
        // SELinux 拦, 只能通过 ConnectivityManager 查当前网络的默认路由。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "iris/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDefaultGateway" -> result.success(defaultGateway())
                    else -> result.notImplemented()
                }
            }

        pictureInPictureChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "iris/picture_in_picture",
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isSupported" -> result.success(pictureInPictureSupported())
                        "setAutoEnter" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            val aspectRatio =
                                call.argument<Double>("aspectRatio") ?: (16.0 / 9.0)
                            setAutoEnter(enabled, aspectRatio)
                            result.success(null)
                        }
                        "enter" -> result.success(
                            enterPictureInPicture(call.argument<Double>("aspectRatio")),
                        )
                        else -> result.notImplemented()
                    }
                }
            }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()

        // API 31 起系统自己接管 (setAutoEnterEnabled), 这里什么都不做;
        // 26..30 没有那个开关, 只能在"用户正要离开"的这一帧进小窗。
        // 再往前 (API < 26) 根本没有画中画, 判断在 enterPictureInPicture 里。
        if (autoEnterPictureInPicture &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S
        ) {
            enterPictureInPicture(null)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Flutter 侧据此收起标题栏 / 控制栏 / 手势层 (见 PictureInPictureOverlay)。
        pictureInPictureChannel?.invokeMethod(
            "onPictureInPictureModeChanged",
            isInPictureInPictureMode,
        )
    }

    private fun pictureInPictureSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun setAutoEnter(enabled: Boolean, aspectRatio: Double) {
        autoEnterPictureInPicture = enabled
        updateAspectRatio(aspectRatio)
        if (!pictureInPictureSupported()) return

        // 每次条件变化都重设一遍参数: API 31+ 的 autoEnter 就在参数里,
        // 而 aspectRatio 也会随片子变化。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            runCatching { setPictureInPictureParams(buildParams()) }
        }
    }

    private fun updateAspectRatio(aspectRatio: Double) {
        if (!aspectRatio.isFinite() || aspectRatio <= 0.0) return
        // 和 Dart 侧 resolvePictureInPictureAspect 同一区间:
        // 超出 1:2.39 ~ 2.39:1 时系统会抛 IllegalArgumentException。
        pictureInPictureAspectRatio = aspectRatio.coerceIn(0.42, 2.39)
    }

    private fun buildParams(): PictureInPictureParams {
        val ratio = pictureInPictureAspectRatio
        val builder = PictureInPictureParams.Builder().setAspectRatio(
            Rational((ratio * 1000).toInt().coerceAtLeast(1), 1000),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnterPictureInPicture)
        }
        return builder.build()
    }

    private fun enterPictureInPicture(aspectRatio: Double?): Boolean {
        if (!pictureInPictureSupported()) return false
        if (isInPictureInPictureMode) return true

        aspectRatio?.let { updateAspectRatio(it) }

        return try {
            enterPictureInPictureMode(buildParams())
        } catch (e: Exception) {
            // 已经不在前台 / Activity 正在销毁时系统会抛 IllegalStateException,
            // 个别 OEM 还会对参数挑毛病 (IllegalArgumentException): 一律当作
            // "没进去", 用户回到应用时控制层仍然是正常状态。
            false
        }
    }

    private fun defaultGateway(): String? {
        return try {
            val manager =
                getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                    ?: return null
            val network = manager.activeNetwork ?: return null
            val linkProperties = manager.getLinkProperties(network) ?: return null

            linkProperties.routes
                .firstOrNull { it.isDefaultRoute && it.gateway != null }
                ?.gateway
                ?.hostAddress
        } catch (e: Exception) {
            null
        }
    }
}

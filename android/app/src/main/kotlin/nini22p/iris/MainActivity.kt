package nini22p.iris

import android.content.Context
import android.net.ConnectivityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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

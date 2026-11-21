# 开发验证与 CI

工具链基线：Flutter **3.47.5**、Dart **3.13.4**。最低版本约束见 [pubspec.yaml](../pubspec.yaml)，解析后的依赖见 [pubspec.lock](../pubspec.lock)。Git 依赖固定到提交；不要在修复任务中顺手升级所有依赖。

## 本地轻量验证

在工程根目录执行：

```powershell
flutter pub get --enforce-lockfile
dart run build_runner build
flutter analyze --no-pub
flutter test --no-pub
python -m unittest discover -s test -p '*_test.py'
pwsh -NoProfile -File test/updater_test.ps1
```

Python 和 PowerShell 测试只使用标准库与临时文件，不需要 Android SDK、Visual Studio 或打包工具。Windows 上进行本地 Flutter 单元测试时，如果只需要分析和 widget tests，可以在独立 Flutter 配置中关闭桌面构建目标，避免为 pub 插件链接启用系统开发者模式。不要把该本机配置提交到仓库；CI 使用自己的 Flutter 配置。

SDK、pub cache、分析器配置和临时目录应使用当前用户有写权限的目录。如果对本地工具做目录隔离，配置 `PUB_CACHE`、`APPDATA`、`LOCALAPPDATA`、`TEMP` 和 `TMP`，并仅在当前 shell 生效。不要把 token、签名文件或本机绝对路径写进项目。

[更新器回归](../test/updater_test.ps1) 验证发布 URL 与哈希要求、备份、覆盖失败时回滚、ZIP 路径穿越拒绝。测试在独立临时目录运行，不更新真实 IRIS 安装。保留失败时的 fixture 便于检查。

[短视频调度回归](../test/short_video_pool_scheduler_test.dart) 使用可控制完成时序的播放器替身，检查当前项优先、邻项串行、过期请求合并及后台卸载/恢复，包含后台停止出帧的生命周期场景；它不证明真实解码器和 GPU 资源占用。[目录扫描回归](../test/directory_scan_test.dart) 检查媒体筛选先于元数据读取、默认保留封面图片、枚举与批次取消，并用本地 HTTP 服务验证挂起的 WebDAV 搜索请求被取消。SAF 列表接口不支持中断已发出的平台调用，只能在返回后丢弃过期结果。

## CI 构建与签名

[CI workflow](../.github/workflows/ci.yml) 对 main、dev、fix 分支、PR 和手动运行执行分析与测试，再构建 Windows/Android。PR 的 Android 验证使用 debug APK，不需要发布密钥。受信分支的发布构建需要 `KEYSTORE`、`STORE_PASSWORD`、`KEY_PASSWORD`、`KEY_ALIAS` secrets；缺失时明确失败，不产出伪装成正式包的无签名 APK。

签名配置由 [prepare_signing.py](../.github/scripts/prepare_signing.py) 从环境变量生成，正确转义空白、反斜杠及 Unicode，并在构建后删除。不要把这些文件加入 Git。

Windows 制品为便携 ZIP、安装器、MSIX；Android 制品为三个 ABI 的 APK。正式发布仅在 main push、版本 tag 尚不存在且构建全部通过时创建；现有版本不会被覆盖。新 tag 显式绑定当前 `github.sha`。修改版本前同步安装器/MSIX 版本和 [更新日志](../CHANGELOG.md)。

## 便携更新的边界

应用精确选择 `IRIS-windows.zip`，只在 GitHub 元数据包含合法 SHA-256 digest、URL 绑定该版本且新更新器存在时提供自动更新。缺少 digest 时仍可打开发布页手动下载。

[PowerShell 更新器](../windows/iris-updater.ps1) 使用独立暂存目录，验证下载哈希和 ZIP 路径，等待原应用退出后备份将覆盖的文件；覆盖失败时尝试回滚。备份和恢复计划保留在更新器输出的位置。若回滚受阻或系统在文件替换期间断电，应从恢复目录或完整便携包恢复。SHA-256 防止下载损坏及确认后资产变化，不代替发布者签名；无法抵抗 GitHub 发布权限和元数据同时被接管。

更新器遵守系统 PowerShell 执行策略。应用等待启动握手，策略阻止脚本执行时保持原应用运行并显示下载错误，不修改系统执行策略。安装器/MSIX 不包含便携更新器。

## 平台回归

自动测试不能代替以下检查：

- Android 与 Windows 的真实 libmpv 网络错误、无效证书、自签名证书和跨域重定向。
- 播放中快速切换普通/短视频模式、清空队列、双指打断拖动、关闭窗口后的最终进度。
- 短视频弱网/高码率首帧与快速跨页；非画中画切后台后邻项卸载，恢复时当前项播放/暂停意图不变。`stop` 卸载邻项媒体，但仍保留可复用播放器和视频输出；实际 RSS、纹理/解码器占用与首帧延迟需要设备测量。
- 大型混合目录、网络盘与 USB 的首屏时间，导航/刷新后旧扫描的剩余 I/O；已发出的本地 `stat` 不能强制中断，取消后不再启动下一批。
- Android SAF 授权跨重启、画中画、全文件权限与用户拒绝后的替代路径。当前历史保守排除没有持久授权记录的 content URI。
- Windows 从媒体目录启动应用后更新、长路径/中文路径、杀进程/断电恢复和文件被占用。
- macOS sandbox 签名包的网络、用户选定目录与文件访问；Linux/macOS 实际挂载磁盘发现。当前发行 CI 只构建 Android/Windows。

保留 SDK、依赖和当前增量缓存。先记录失败端点/命令，再决定是否清理缓存；不要因网络失败删除唯一可复用的下载。

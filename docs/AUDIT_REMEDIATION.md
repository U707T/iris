# 2026-11-21 审计修复记录

本次工作基于 v2.8.2 源码快照，修复审计中的安全、数据完整性、播放时序和发行配置问题。

| 原审计项 | 修复方式 | 主要回归 |
|---|---|---|
| P1-1 WebDAV 新密码发给旧主机 | 请求前验证 scheme/host/port；普通播放、短视频、音频封面使用同一安全接口 | [存储数据安全](../test/storage_data_safety_test.dart) |
| P1-2 HTTP Basic 明文风险 | 新连接默认 HTTPS；HTTP 须明确确认，保留密码空白；原生网络播放设置/读回 TLS 校验 | [WebDAV 界面](../test/webdav_dialog_security_test.dart)、[TLS](../test/playback_tls_test.dart) |
| P2-1 后端错误不反馈 | 订阅 error stream 并绑定装载 generation，在 UI 呈现可重试状态 | [装载会话](../test/playback_load_session_test.dart)、[短视频池](../test/short_video_pool_lifecycle_test.dart) |
| P2-2 停止/卸载不取消旧装载 | generation/alive 校验；以暂停方式 open，当前会话再决定播放 | [装载会话](../test/playback_load_session_test.dart) |
| P2-3 迟到读取覆盖用户状态 | mutation 在 Store ready 后才计算新状态；显式 flush 返回失败 | [存储数据安全](../test/storage_data_safety_test.dart) |
| P2-4 混合队列刷新误删 | 扫描范围限定到连接/目录，Windows 本地路径规范化，远程路径保持大小写 | [目录 IO](../test/refresh_play_queue_io_test.dart)、[混合场景](../test/storage_data_safety_test.dart) |
| P2-5 替换失败丢原档 | 替换前保留 .bak，缺正式文件时读备份；最新编码/写入错误不会被旧成功写抹掉 | [持久化](../test/persistence_test.dart)、[故障注入](../test/storage_data_safety_test.dart) |
| P2-6 Windows 半迁移 | 独立完成标志、逐文件暂存、跳过已有新档，中断后重试 | [存储数据安全](../test/storage_data_safety_test.dart) |
| P2-7 非 Windows 磁盘列表为空 | 移除遮蔽的局部列表 | [本地存储实现](../lib/models/storages/local.dart)；挂载盘需平台实测 |
| P2-8 FTP 坏项组合/停止态 | 清洗阶段逐项验证并保留 -1 停止态 | [旧类型清洗](../test/legacy_storage_purge_test.dart)、[组合用例](../test/storage_data_safety_test.dart) |
| P2-9 退出没等保存 | 两种播放模式均 await 历史 add + flush | [历史保存](../test/playback_history_test.dart)、[短视频写入](../test/short_video_pool_lifecycle_test.dart) |
| P2-10 旧 seek 恢复新状态/预览残留 | session + media identity 校验，共享预览按所有权清理 | [Seek 生命周期](../test/seek_session_lifecycle_test.dart) |
| P2-11 双指中断 | 识别器按 pointer 区分拒绝，主指取消向上通知 | [识别器生命周期](../test/player_drag_recognizer_lifecycle_test.dart)、[真实手势](../test/player_gesture_test.dart) |
| P2-12 重复文件连播卡住 | 加载 effect 包含队列 entry index | [重复播放项](../test/playback_entry_effect_test.dart) |
| P2-13 短视频暂停状态泄漏 | 当前文件失效时同时释放 active identity 并重置 userPaused | [短视频池](../test/short_video_pool_lifecycle_test.dart) |
| P2-14 旧翻页动画覆盖新命令 | 最新目标取消旧动画，区分用户和程序化滚动提交 | [PageController 回归](../test/short_video_page_sync_test.dart) |
| P2-15 音量异步退出 | 读取/写入前后检查存活状态和会话 | [音量](../test/short_video_volume_test.dart) |
| P2-16 更新目录/完整性/恢复 | 绝对目录、版本 URL + SHA-256、启动握手、ZIP 路径限制、备份和异常回滚 | [更新事务](../test/updater_test.ps1) |
| P2-17 附件顺序错配 | 精确选择便携 ZIP，显示和执行同一 URL/大小 | [版本和资产](../test/version_check_test.dart) |
| P2-18 fork PR 签名失败 | PR 构建 debug；受信发布才准备签名，环境变量安全转义 | [CI 配置](../.github/workflows/ci.yml)、[签名脚本测试](../test/ci_helpers_test.py) |
| P2-19 发布 tag/构件错配 | target_commitish 绑定 github.sha，并按 ref 串行运行 | [CI 配置](../.github/workflows/ci.yml) |
| P2-20 浮动第三方 Action | 固定完整 SHA，移除 yq/master 和第三方 tag 查询，默认只读权限 | [CI 配置](../.github/workflows/ci.yml) |
| P2-21 macOS entitlement 缺失 | 补 network.client 与用户选定文件只读权限 | [正式 entitlements](../macos/Runner/Release.entitlements)；需签名包实测 |

补充修复：删除存储后清理关联收藏/当前对象，旧 WebDAV 历史无法再制造非法本地存储对象；短视频空队列立即暂停；临时 content URI 不写入历史；移除未使用的 WRITE_SETTINGS 权限并限定旧存储权限版本；统一 SDK 下限并固定 Git 依赖提交，更新隐私说明。

## 本地验证结果

2026-11-21，Flutter 3.47.5 / Dart 3.13.4：

- `flutter pub get --enforce-lockfile` 成功；`dart run build_runner build` 成功。
- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub --reporter expanded`：296 项通过。
- `python -m unittest discover -s test -p '*_test.py'`：3 项通过。
- `test/updater_test.ps1`：发布源、备份、占用回滚、ZIP 路径安全检查通过。
- actionlint v1.7.12：CI 配置检查通过；`git diff --check` 通过。

本地未执行 Android/Windows 平台编译，交由 CI。

## 保留的边界

- 保留上游安装标识，避免未经迁移设计改变用户的安装身份/数据目录；如需独立共存产品，应单独设计签名和数据迁移方案。
- SHA-256 校验用于下载完整性和确认后的资产绑定，不等同于独立发布者签名。当前没有新增签名私钥或伪造签名流程。
- 显式开启 TLS 并读回配置的测试不能证明所有发行 libmpv/FFmpeg 构建都通过无效证书及跨域重定向实测。
- 更新中断/回滚被文件占用阻止时，保留恢复计划和备份；断电恢复仍需人工或完整便携包恢复。
- Android/Windows 原生媒体、macOS sandbox 与 Linux/macOS 挂载盘等实机检查见 [开发验证与 CI](TESTING.md)。依赖 CVE 与发行物 Authenticode 检查不在本轮本地测试结论内。

## v2.8.3 性能优化更改审计

范围：相对 v2.8.2 的短视频调度与后台卸载、目录读取与取消、队列定位缓存、Flutter 资源和版本配置。执行实现自查与两个模块的交叉只读复核，不视为全仓重新审计。

| 复核中发现的边界 | 修复与证据 |
|---|---|
| 后台停止出帧，生命周期重建及帧后回调不能及时卸载 | 直接监听生命周期和画中画状态，用微任务执行卸载；[调度回归](../test/short_video_pool_scheduler_test.dart) 断言禁帧、无宿主重建时邻项仍停止 |
| 远距离跳页可能选中尚在装载的槽位 | 优先选可立即使用的槽；回归在旧预载尚未完成时跳到第 11 条 |
| 队列缩短后未复用的旧邻项仍保留媒体 | 统一释放映射、订阅和媒体，槽位 open/stop 串行；覆盖三条替换为一条及迟到错误 |
| 清空后下一帧之前退出可能漏写已暂存历史 | dispose 无条件 flush；覆盖 clear 后直接 dispose、无中间帧 |
| 过滤可能误伤封面，取消可能越过批次或影响别的请求 | 默认全量接口保留，媒体读取显式选择；[目录扫描回归](../test/directory_scan_test.dart) 核对 stat 次数、枚举终止和真实 WebDAV 传输取消 |

确认没有新增依赖，锁文件与生成模型没有漂移。队列定位缓存键覆盖队列和当前项；MSIX 从源图片读取安装图标，不依赖被缩减的 Flutter 资源清单。

边界：保留三播放器和视频输出，`stop` 仅卸载媒体。media_kit 原生操作仍有共享锁，复用控制器的首帧通知也不是每个新媒体的独立呈现确认；本次只保证池调度优先级，不宣称首帧时延、RSS 或耗电的具体改善。已发出的本地 stat 和 SAF 平台调用无法强制中断。设备测量和验收项见 [开发验证与 CI](TESTING.md)。

本轮本地验证（2026-11-21，Flutter 3.47.5 / Dart 3.13.4）：离线锁定依赖解析、build_runner、静态分析通过；完整 Flutter 回归 310 项通过；Python 辅助脚本 3 项通过，PowerShell 更新器事务回归通过。Android/Windows 平台构建交由本版 CI 执行，发布后另核对制品，真机性能未测量。

## v2.8.4 主模式导航与同类生命周期修复

已复现：主模式切换上一条/下一条时，队列索引改变，但新会话没有执行打开媒体。当前 flutter_hooks 在本帧先初始化新的 keyed effect，再于 build 收尾清理旧 effect；旧清理无条件 invalidate 共用装载会话，取消了刚启动的新会话。新装载改为在微任务执行，并检查 effect 是否仍存活，让旧清理先完成，保留过期会话和卸载后的取消保护。

| 同类审计与修复 | 验证 |
|---|---|
| 上一条/下一条、首尾环绕、非连续索引、重复文件和停止后重新导航 | [队列导航](../test/main_player_navigation_test.dart)、[装载 effect 与真实会话](../test/playback_entry_effect_test.dart)；自动连播、按钮、键盘及列表选择均复核到同一装载入口 |
| 新媒体慢装载时错误地向旧媒体恢复新进度 | 成功装载 identity 匹配文件及队列条目后才允许续播；[慢装载与重复条目恢复](../test/playback_navigation_progress_test.dart) |
| 慢装载期间保存把旧媒体进度写入新历史 | 保存调用时动态核对成功装载归属，保留旧条目正常 cleanup 保存；回归覆盖未完成新项的显式保存与完成后复用同一保存回调 |
| 统计开关的旧清理取消新定时器 | effect 持有自己的局部 Timer；[开启、持续轮询、关闭与重开](../test/player_stats_lifecycle_test.dart) |
| 普通/短视频宿主切换时旧清理清空新画中画回调 | 注销前核对回调所有权；[宿主替换与回调状态](../test/picture_in_picture_lifecycle_test.dart) |

同时核对键盘与媒体键共用的队列入口、随机顺序定位、短视频池 token 调度、手势会话和播放器交接保护，未确认它们存在独立的相同导航故障。保留队列定位缓存；根因不在缓存键或 Provider 选择器。

验证使用受控媒体后端和内存存储，覆盖真实 hook 与会话的组合时序及队列导航；临时按钮组合用例中的切换断言通过，但因夹具清理问题未保留为最终套件，最终分别验证真实队列和装载入口。不等于 Android/Windows 原生解码与系统画中画的设备验收。修复及独立复核后按 v2.8.4 发布，平台构建交由 CI，发布后核对标签与制品。

本轮最终本地验证：`flutter analyze --no-pub` 无问题；`flutter test --no-pub --reporter expanded` 共 316 项全部通过；`git diff --check` 通过。主故障与慢装载续播测试均在修复前复现失败，修复后通过。发布前独立复核进一步补上历史保存的动态归属检查，完整 316 项回归再次通过；补充用例验证慢 B 保存、跳过 B、返回 B 完成后复用初始保存回调，A/B 历史均保持正确。离线锁定依赖、代码生成、Python 3 项和 PowerShell 更新器事务回归通过，未新增依赖或改变媒体格式。

## v2.8.5 短视频滑动与闪帧优化

范围：v2.8.4 之上的短视频翻页与页面渲染，保留原解码器、依赖和三播放器池。审计及验证后按 v2.8.5 发布。

- 手指抬起后的惯性滚动仍会跨过半页；原 `onPageChanged` 会提前更新队列，再被页面同步的 `jumpToPage` 截断。现在用户翻页只在 `ScrollEnd` 停稳后提交一次，取消和反向滑动不提交放弃的中间页。已停稳的同页同步直接返回，保留外部快捷键/滚轮的程序化翻页和反向取消。
- 开启 PageView 的一屏隐式缓存，提前挂载相邻画面；测试确认 100 条队列不会全量创建页面。仍只使用原有三播放器池。
- 槽位已分配不代表新媒体已装载。页面在装载中、待打开、错误、文件/页码不匹配时用不透明黑底覆盖渲染器，池存在却缺少槽位时不再借用当前活动播放器。覆盖期间保留渲染器挂载，避免反复销毁纹理及其订阅。

发布前独立审计补强：Flutter 在惯性滚动途中被再次按住时也会发出 ScrollEnd；仅接受精确页边界上的结束，非整数页保留滚动会话，避免过半后反向操作误提交。开启隐式缓存后，无障碍/焦点的 showOnScreen 也能移动页面；显式区分应用同步与隐式滚动，防止画面已翻页但播放索引不跟随。

[翻页回归](../test/short_video_pager_test.dart) 检查真实 fling 中途不提交、停稳仅提交一次、取消/反向拖动、过半后按住/松开、程序化导航与 showOnScreen 的播放索引同步；[画面回归](../test/short_video_pool_page_test.dart) 检查遮罩及加载前后渲染器实例保留；[同步回归](../test/short_video_page_sync_test.dart) 保留快速反向动画并检查同页无额外滚动活动。

边界：媒体库复用控制器的首帧 Future 只在控制器生命周期内完成一次；本次遮罩处理明确的装载中窗口，不把装载完成等同于该媒体新帧已提交到 GPU。原生纹理呈现、弱网下的黑底等待与实际滑动帧时仍需 Android/Windows 设备验证，不能由 widget 测试宣称零闪帧或帧率提升。

2026-11-21，优化实现阶段定向回归 25 项及完整 324 项通过。发布前独立复核补强了过半后按住/松开与隐式焦点翻页，最终 `flutter analyze --no-pub` 无问题，`flutter test --no-pub --reporter expanded` 完整 327 项全部通过；锁定依赖解析、代码生成、Python 3 项和 PowerShell 更新器事务回归通过。`git diff --check` 通过，无未解决的审计阻断项。Android/Windows 正式构建交由本版 CI，真实设备帧时未测量。

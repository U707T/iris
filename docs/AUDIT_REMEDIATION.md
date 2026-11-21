# 2026-11-21 审计修复记录

本次工作基于 v2.8.1 源码快照，修复审计中的安全、数据完整性、播放时序和发行配置问题。应用版本暂不递增，已有 tag/release 不覆盖；推送后由 CI 生成供验证的构件。

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

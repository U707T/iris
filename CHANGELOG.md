## v1.8.2-rc.4

### Changelog

* Full dependency modernization: the media stack (media_kit_video 2.0 / fvp 0.38 / video_player 2.14), secure storage (flutter_secure_storage 11), file picker (file_picker 13), permissions (permission_handler 13), network drives (saf_util 3, win32 6), links (app_links 7) and all other dependencies are now up to date
* The UI migrated to Flutter's new standalone `material_ui` package (the Material library is moving out of the Flutter SDK); the look & feel is expected to stay the same — please report any visual differences you spot
* Note: because of the secure storage upgrade, local playback history / settings will reset once on the first launch after this update

### 更新日志

* 依赖全面现代化：播放栈（media_kit_video 2.0 / fvp 0.38 / video_player 2.14）、安全存储（flutter_secure_storage 11）、文件选择（file_picker 13）、权限（permission_handler 13）、网络盘（saf_util 3、win32 6）、链接（app_links 7）等全部依赖升级到最新
* 界面迁移到 Flutter 新的独立 `material_ui` 包（Material 库正从 SDK 拆出）；预期观感不变，如有样式差异请反馈
* 注意：由于安全存储组件大版本升级，本次更新后首次启动会重置一次本地播放历史 / 设置（一次性）

## v1.8.2-rc.3

### Changelog

* Short video mode on PC: the mouse wheel now switches videos wherever the pointer is in the mode — including over the bottom info bar, the progress bar area and the side buttons, which previously ignored scrolling (a code-review follow-up on rc.2)

### 更新日志

* 短视频模式 PC 端：鼠标滚轮现在在界面任意位置都能切换视频——包括此前无响应的底部信息栏、进度条区域和侧边按钮（对 rc.2 的代码复查跟进）

## v1.8.2-rc.2

### Changelog

* Short video mode: the loop / speed / volume settings are now applied before the video is opened, so the first video can no longer briefly play at the default volume right after entering the mode (a code-review follow-up on rc.1)
* The amount of player commands per switch is reduced, so the first video also starts a bit faster

### 更新日志

* 短视频模式：在打开视频前先应用循环 / 倍速 / 音量设置，修复进入模式后首个视频可能短暂以默认音量播放的问题（对 rc.1 的代码复查跟进）
* 减少每次切条的播放器命令往返，首个视频起播也更快

## v1.8.2-rc.1

### Changelog

* Fixed the rare case where the first video in short video mode could not be scrubbed (its duration could stay unknown): the progress bar now recovers automatically, and duration is re-synced with a fallback even if the player misses the event
* Seeking no longer jumps to the start while the duration is not yet known, and the first video starts playing sooner when entering the mode
* After releasing the progress bar, it no longer snaps back before the seek lands
* This is a release candidate (RC) build for testing before the next stable release

### 更新日志

* 修复短视频模式中首个视频偶发无法拖动进度条的问题（时长信息可能一直未就绪）：进度条现在会自动恢复，即使播放器漏报事件也会兜底同步时长
* 时长未知时跳转不再误跳到开头；进入模式时首个视频开始播放更快
* 松手后进度条不再先回跳再跳转（等到实际跳转生效后再收起预览）
* 本版本为候选发布版（RC），用于正式版发布前的测试验证

## v1.8.1

### Changelog

* Much smoother progress bar scrubbing in short video mode: playback pauses while you drag, the bar / thumb / time bubble follow your finger in real time, preview seeks are throttled, and playback resumes exactly where you release
* Fixed the mismatched bright band near the progress bar in landscape: the footer gradient now also covers the progress bar area, blending the darkening into the video evenly
* Added fade transitions for the loading indicator, the long-press speed hint and entering short video mode

### 更新日志

* 短视频模式进度条拖动大幅优化：拖动时自动暂停播放，进度条 / 圆点 / 时间气泡实时跟手，预览跳转做了节流，松手后精确跳转并恢复播放
* 修复横屏下进度条区域与视频亮度不一致的"亮条"问题：底部渐变现在覆盖进度条区域，暗部与视频衔接自然
* 加载指示、长按倍速提示、进入短视频模式增加淡入淡出过渡

## v1.8.0

### Changelog

* Short video mode now uses a preload player pool (previous / current / next): swiping is seamless and the adjacent videos are visible while dragging — no more loading gap between videos (Media Kit backend; FVP keeps the lightweight behavior)
* The progress bar is draggable: drag it to scrub (with a thumb and a time bubble) or tap it to jump to a position
* Long-press speed-up now shows a speed indicator overlay
* The playback progress of recycled videos is saved automatically, and the mode switches the player cleanly when entering / leaving

### 更新日志

* 短视频模式升级为预载播放器池（上一条 / 当前 / 下一条）：滑动切换无缝衔接，滑动过程中即可看到下一条画面，不再出现切条加载空白（Media Kit 后端；FVP 后端保持轻量模式）
* 进度条支持直接拖拽调进度（带拖动圆点和时间气泡），点击进度条可直接跳转
* 长按倍速播放新增速度指示浮层
* 槽位被复用的视频会自动保存播放进度；进入 / 退出短视频模式时播放器切换更干净

## v1.7.0

### Changelog

* Short video mode (Douyin style): one video per screen with vertical swipe navigation — enter it from the new button on the control bar or the ⋮ menu
* The feed plays the videos of the current play queue (audio files are skipped); each video loops, so it plays like a short-video app
* Feed gestures: swipe up / down to switch videos (mouse wheel or ↑ / ↓ keys on desktop), tap to play / pause, double-tap to seek, long-press to speed up, drag horizontally to scrub
* Leave the mode with the back button, Esc, or the Android back gesture, and return to the normal player
* Videos in short video mode always play from the beginning (no resume); works with both the Media Kit and FVP playback backends

### 更新日志

* 新增短视频模式（抖音式竖向信息流）：一屏一条视频、上下滑动切换，入口在控制栏新按钮和 ⋮ 菜单中
* 信息流播放当前播放列表里的视频（自动跳过音频），单条循环播放
* 模式内手势：上下滑动切换（桌面端可用滚轮或 ↑ / ↓ 键）、单击播放/暂停、双击快进快退、长按倍速、左右拖动调节进度
* 返回键 / Esc / Android 返回手势退出模式，回到普通播放器界面
* 短视频模式内视频始终从头播放（不续播），Media Kit / FVP 两种播放后端均可用

## v1.6.1

### Changelog

* Playback stats overlay (Ctrl + I) now shows and hides instantly
* Double-tap fast-forward / rewind now follows the configurable skip duration
* Screenshots now respect rotation / flip, and save more reliably on Android (falls back to the app folder without the "all files access" permission)
* Shortcuts panel corrections: F opens storages; the panel can be opened with Shift + ?
* Screenshot image encoding moved off the UI thread to reduce jank

### 更新日志

* 播放统计浮层（Ctrl + I）现在即开即用，立即显示/隐藏
* 双击快进/快退遵循"快进/快退时长"设置
* 截图会跟随画面旋转/镜像；Android 上保存更稳（无"所有文件访问"权限时自动回退到应用目录）
* 修正快捷键面板（存储为 F；面板本身可用 Shift + ? 打开）
* 截图编码移到后台线程，减少卡顿

## v1.6.0

### Changelog

* Screenshot: capture the current frame (Ctrl + S) and save it to your pictures folder
* Rotate / flip the video: rotate 90°/180°/270°, or mirror horizontally / vertically (Ctrl + T)
* Playback stats overlay: resolution, frame rate, dropped frames, decoder, bitrate (Ctrl + I)
* Configurable skip duration for keyboard and gesture seeking, with a separate step for Shift
* History popup: clear all history, and a proper empty state
* Keyboard shortcuts reference panel (? on desktop)
* Pure black (OLED) theme option that saves power on OLED screens
* Refreshed dependencies for better performance and stability
* Reduced runtime overhead: verbose player logging is now disabled in release builds

### 更新日志

* 截图：一键截取当前画面（Ctrl + S）并保存到图片目录
* 画面旋转/翻转：90°/180°/270° 旋转，以及水平/垂直镜像（Ctrl + T）
* 播放统计浮层：分辨率、帧率、丢帧、解码器、码率（Ctrl + I）
* 快进/快退时长可自定义，按住 Shift 使用另一档步长
* 播放历史支持一键清空，并新增空状态提示
* 新增快捷键参考面板（桌面端按 `?`）
* 新增纯黑（OLED）主题，OLED 屏幕更省电
* 升级依赖，提升性能与稳定性
* 降低运行开销：release 版本默认关闭播放器详细日志

## v1.5.3

### Changelog

* Long-press the screen to speed up playback, and the long-press speed can be configured in settings
* Manually and smoothly zoom the video (pinch to zoom, Ctrl + scroll wheel, or the zoom button)
* Search videos and audio in the current folder
* Remember window size and position (can be disabled in settings)

### 更新日志

* 长按屏幕加速播放，长按倍速可在设置中调整
* 可手动无极调节画面缩放（双指捏合、Ctrl + 滚轮、或缩放按钮）
* 支持在当前文件夹搜索视频和音频
* 记住窗口大小和位置（可在设置中关闭）

## v1.5.2

### Changelog

* Migrate to MPL-2.0 license
* Add more media type support
* Fix key open subtitle and audio track issue
* Fix popup layer cannot be closed with `Esc` key issue

### 更新日志

* 迁移到 MPL-2.0 许可证
* 添加更多媒体类型支持
* 修复按键打开字幕和音频轨道的问题
* 修复弹出层无法使用 `Esc` 键关闭的问题

## v1.5.1

### Changelog

* Adjusted the playback control bar style in compact layout
* Clicking “Check update” in the Microsoft Store version redirects to the Store page
* Fixed forward and backward issues

### 更新日志

* 调整了紧凑布局下的播放控制栏样式
* 微软商店版本中点击检查更新将跳转至商店页面
* 修复了快退快进的问题

## v1.5.0

### Changelog

* Updated app icon
* Added a stop and an exit button
* Added a playback-speed selector that activates with a touch-and-hold gesture
* Fixed URI handling
* Improved stability and performance

### 更新日志

* 更换应用图标
* 添加停止按钮和退出按钮
* 添加触控长按激活的播放速度选择器
* 修复 uri 处理
* 优化了稳定性和性能

## v1.4.2

### Changelog

* Fix audio cover issue
* Improve uri handling

### 更新日志

* 修复音频封面问题
* 改进 uri 处理

## v1.4.1

### Changelog

* Dynamic FTP streaming url

### 更新日志

* FTP 串流使用动态 url

## v1.4.0

### Changelog

* Supports FTP storage
* Supports adding local folders to the storage list
* Storage list support remote disk and network shortcuts on Windows
* Add Windows installer

### 更新日志

* 支持 FTP 存储
* 支持添加本地文件夹到存储列表
* Windows 版本存储列表支持远程磁盘和网络快捷方式
* 添加 Windows 版本安装器

## v1.3.4

### Changelog

* The Android version allows you to set the screen orientation.
* Add playback speed button.
* Add hotkeys: Step forward `+`, Step backward `-`.

### 更新日志

* 安卓版本可以设置屏幕方向。
* 添加播放速度按钮。
* 添加快捷键：帧进 `+`，帧退 `-`。

## v1.3.3

### Changelog

* Fix issue of not being able to continue playback after startup

### 更新日志

* 修复启动后无法继续播放的问题

## v1.3.2

### Changelog

* Support for custom https ports when adding WebDAV storage

### 更新日志

* 添加 WebDAV 存储时支持自定义 https 端口

## v1.3.1

### Changelog

* The data save location for the Windows version has been changed to `C:\Users\<user>\AppData\Roaming\nini22P\iris`
* Updated upstream dependencies and fixed the issue with switching subtitles in the FVP player backend

### 更新日志

* Windows 版本数据保存位置已修改为 `C:\Users\<user>\AppData\Roaming\nini22P\iris`
* 更新上游依赖，修复 FVP 播放器后端切换字幕的问题

## v1.3.0

### Changelog

* Add [FVP](https://github.com/wang-bin/fvp) player backend (Experimental, with unknown bugs)
* Adding volume adjust
* Add file sort
* Add hotkeys: Volume up ( `Arrow Up` ), Volume down ( `Arrow Down` ), Volume mute ( `Ctrl + M` ), Toggle always on top ( `F10` ), Close currently media file ( `Ctrl + C` ), Exit application ( `Alt + X` )
* Improved some visual effects

### 更新日志

* 添加 [FVP](https://github.com/wang-bin/fvp) 播放器后端（实验性，有未知bug）
* 添加音量调整
* 添加文件排序
* 添加快捷键：提升音量（ `Arrow Up` ）、降低音量（ `Arrow Down` ）、静音（`Ctrl + M`）、切换窗口置顶（ `F10` ）、关闭当前媒体文件（ `Ctrl + C` ）、退出应用（ `Alt + X` ）
* 改进了部分视觉效果

## v1.2.1

### Changelog

* Split APKs by architecture to reduce installation size.

### 更新日志

* 拆分不同架构的 APK 以减小安装包大小

## v1.2.0

### Changelog

* Support jumping to video playback from external clicks (Windows version can play by command line or dragging files to the window)
* Support adjusting brightness and volume gestures (Brightness gestures are not available on Windows version)
* Support playing online links
* Add an option to always start playback from the beginning
* On Android 11 and above, file reading is changed to using the "Manage All Files" permission
* Improved WebDAV connection test function
* Improved some visual effects

### 更新日志

* 支持从外部点击视频跳转播放（Windows 版本可以通过命令行或者拖拽文件到窗口播放）
* 支持调整亮度和音量手势（Windows 版本调整亮度手势不可用）
* 支持播放在线链接
* 添加总是从头开始播放的选项
* Android 11 以上读取文件时改为使用 `管理所有文件` 权限
* 改进 WebDAV 测试连接功能
* 改进了部分视觉效果

## v1.1.1

### Changelog

* Restore old update method for windows version (Double-click the `iris-updater.bat` in the same directory as the executable file to upgrade if you have problems updating.)

### 更新日志

* windows 版本恢复为旧的更新方式（更新出问题的可双击打开可执行文件同级目录下的 `iris-updater.bat` 升级）

## v1.1.0

### Breaking Changes

* All configurations will be cleared. Please reconfigure

### Changlog

* Display all local storage
* Support playback history
* Support random playback
* Support loop playback
* Support video zoom

### 重大变更

* 所有配置将被清空，请重新配置

### 更新日志

* 显示所有本地存储
* 支持播放历史
* 支持随机播放
* 支持循环播放
* 支持视频缩放

## v1.0.3

### Changelog

* Improve Windows version installation updates
* Fixes an issue where subtitles may not be found

### 更新日志

* 改进 Windows 版本安装更新
* 修复可能无法找到字幕的问题

## v1.0.2

### Changelog

* Support for switching built-in audio tracks
* Reduce package size for Windows version

### 更新日志

* 支持切换内置音轨
* 减小 Windows 版本包体大小

## v1.0.1

### Changelog

* Windows version support auto update

### 更新日志

* Windows 版本支持自动更新

## v1.0.0

### Changelog

* Supports WebDAV and local storage video playback

### 更新日志

* 支持 WebDAV 和本地存储视频播放

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

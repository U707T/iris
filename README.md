<img height="100px" width="100px" alt="logo" src="./assets/images/logo.png"/>

# IRIS - 轻量级视频播放器

[![CI](https://github.com/U707T/iris/actions/workflows/ci.yml/badge.svg)](https://github.com/U707T/iris/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/U707T/iris)](https://github.com/U707T/iris/releases/latest)
[![License](https://img.shields.io/github/license/U707T/iris)](./LICENSE)

[English](./README_EN.md) | 中文

IRIS 是一款基于 Flutter 的轻量级视频播放器。本仓库是 [nini22P/iris](https://github.com/nini22P/iris) 的增强分支：在保持上游功能的基础上，加入**短视频模式**与一系列播放体验、稳定性改进；Windows / Android 安装包由本仓库 CI 自动构建发布。

## 特性

- [X] 基于 [Media Kit](https://github.com/media-kit/media-kit) | [FVP](https://github.com/wang-bin/fvp)，可播放多种视频格式
- [X] 本地存储与 WebDAV
- [X] **短视频模式**：竖滑无缝切换、单条循环、进度条拖拽、双击快进 / 快退反馈、长按倍速光效、音量按钮
- [X] 可切换音轨
- [X] 播放队列支持随机和重复
- [X] 完善的手势支持
- [X] 长按加速播放（倍速可自定义）
- [X] 无级画面缩放
- [X] 截图、画面旋转 / 翻转
- [X] 播放统计（帧率、丢帧、解码器）
- [X] 文件搜索
- [X] 窗口大小和位置记忆
- [X] 快进 / 快退时长可自定义
- [X] 纯黑（OLED）主题

### 本分支的主要增强

- **短视频模式**：控制栏按钮进入，预载播放器池带来竖滑无缝切换；进度条可拖拽 / 点击定位；双击画面左 / 右侧快退 / 快进并显示「±Ns」提示；长按倍速带呼吸光效；音量按钮长按后上下滑动调节设备音量（桌面端悬停滚轮微调）
- **播放启动更稳**：视频先以暂停方式打开、等首帧就绪后再播放，避免「有声音但画面黑着」；预载的相邻视频也会先解出首帧
- **随机播放重做**：每次开启随机都会重新洗牌（当前视频排最前），启动时随机开着也会重洗一次；关闭后恢复原始顺序
- **Windows 修复**：内嵌 fvp 修复版解决启动崩溃；内置 Flutter 引擎无障碍崩溃（[flutter/flutter#175041](https://github.com/flutter/flutter/issues/175041)）的兼容规避，默认生效（详见「故障排查」）
- **一批稳定性修复**：播放历史上限、全屏开关、音量浮层、搜索对话框、短视频边界情况等（详见 [CHANGELOG.md](./CHANGELOG.md)）

## 下载

| 平台    | 架构/渠道 | 下载链接                                                                                                           | 备注             |
| :------ | :-------- | :----------------------------------------------------------------------------------------------------------------- | :--------------- |
| Windows | 安装包    | [IRIS-windows-installer.exe](https://github.com/U707T/iris/releases/latest/download/IRIS-windows-installer.exe)     | 64 位系统        |
|         | 便携版    | [IRIS-windows.zip](https://github.com/U707T/iris/releases/latest/download/IRIS-windows.zip)                         | 解压即用         |
| Android | arm64-v8a | [IRIS-android-arm64-v8a.apk](https://github.com/U707T/iris/releases/latest/download/IRIS-android-arm64-v8a.apk)     | 64 位设备         |
|         | armeabi-v7a | [IRIS-android-armeabi-v7a.apk](https://github.com/U707T/iris/releases/latest/download/IRIS-android-armeabi-v7a.apk) | 32 位设备         |
|         | x86_64    | [IRIS-android-x86_64.apk](https://github.com/U707T/iris/releases/latest/download/IRIS-android-x86_64.apk)           | 模拟器 / x86 设备 |

> 安装包由 GitHub Actions 自动构建；带 `-rc` 后缀的为预发布测试版。历史版本见 [Releases](https://github.com/U707T/iris/releases)。

## 键位与手势

### 键位操作

| 键位                   | 描述                                 |
| ---------------------- | ------------------------------------ |
| `Space`              | 播放 / 暂停 / 选择文件               |
| `Arrow Left`         | 快退                                 |
| `Arrow Right`        | 快进                                 |
| `Arrow Up`           | 提升音量                             |
| `Arrow Down`         | 降低音量                             |
| `Ctrl + Arrow Left`  | 上一个                               |
| `Ctrl + Arrow Right` | 下一个                               |
| `Ctrl + X`           | 随机                                 |
| `Ctrl + R`           | 重复                                 |
| `Ctrl + V`           | 视频缩放                             |
| `Ctrl + M`           | 静音                                 |
| `S`                  | 音轨                                 |
| `P`                  | 播放队列                             |
| `F`                  | 存储                                 |
| `Ctrl + O`           | 打开文件                             |
| `Ctrl + L`           | 打开链接                             |
| `Ctrl + C`           | 关闭当前媒体文件                     |
| `Ctrl + H`           | 播放历史                             |
| `Ctrl + P`           | 设置                                 |
| `Ctrl + S`           | 截图                                 |
| `Ctrl + T`           | 旋转画面                             |
| `Ctrl + I`           | 播放统计                             |
| `Shift + ?`          | 快捷键参考                           |
| `+`                  | 帧进                                 |
| `-`                  | 帧退                                 |
| `Enter`              | 进入全屏 / 退出全屏 / 选择文件       |
| `F11`                | 进入全屏 / 退出全屏                  |
| `Esc`                | 退出当前菜单 / 返回上一级 / 关闭全屏 |
| `F10`                | 切换窗口置顶                         |
| `Alt + X`            | 退出应用                             |

### 手势操作

| 手势             | 描述                           |
| ---------------- | ------------------------------ |
| 单击             | 选择项目或打开菜单             |
| 双击屏幕中心     | 播放 / 暂停                    |
| 双击屏幕左侧     | 快退                           |
| 双击屏幕右侧     | 快进                           |
| 左右滑动         | 调整播放进度                   |
| 屏幕左侧上下滑动 | 调整屏幕亮度                   |
| 屏幕右侧上下滑动 | 调整设备音量                   |
| 长按             | 加速播放（倍速可在设置中调整） |
| 双指捏合         | 无级调节画面缩放               |
| `Ctrl` + 滚轮    | 无级调节画面缩放（桌面端）     |

### 短视频模式操作

进入方式：控制栏按钮或「⋮」菜单；`Esc` / 返回键退出。

| 操作                     | 描述                                       |
| ------------------------ | ------------------------------------------ |
| 上下滑动                 | 切换上一条 / 下一条                        |
| 单击 / 双击画面中间      | 播放 / 暂停                                |
| 双击画面左侧             | 快退（步长取设置值，中央显示「±Ns」提示）  |
| 双击画面右侧             | 快进（同上）                               |
| 水平拖动                 | 调整播放进度（画面任意位置均可）           |
| 底部进度条               | 点击 / 拖动定位                            |
| 长按                     | 加速播放（松手恢复）                       |
| 点击音量按钮             | 静音 / 取消静音（仅 IRIS 自身）            |
| 按住音量按钮上下滑动     | 调节设备音量（与系统音量键一致）           |
| 桌面端：滚轮 / `↑` `↓`   | 切换上一条 / 下一条                        |
| 桌面端：悬停音量按钮滚动 | 微调设备音量                               |

## 故障排查

- **Windows：应用启动后立即（或最初几次操作时）闪退**（`flutter_windows.dll` 报 `0xC0000005`）。这是 Flutter 引擎在 Windows 上的已知 bug（[flutter/flutter#175041](https://github.com/flutter/flutter/issues/175041)）：当 UI 自动化客户端（远程桌面工具如 Chrome Remote Desktop / RDP、读屏软件、自动化工具等）在应用启动期间枚举窗口元素时触发。**兼容规避已内置并默认生效，应用开箱即可正常使用**；代价是 IRIS 会关闭自身的 Windows 无障碍集成（屏幕阅读器无法读取应用）。如你确实需要读屏、且愿自担崩溃风险，可显式退出兼容（二选一）：
  - 设置环境变量 `IRIS_ENABLE_WINDOWS_A11Y=1`（例如执行一次 `setx IRIS_ENABLE_WINDOWS_A11Y 1` 后重新启动 IRIS），或
  - 以命令行参数 `--enable-windows-a11y` 启动 IRIS。

  （旧写法 `IRIS_DISABLE_WINDOWS_A11Y=1` / `--disable-windows-a11y` 仍然兼容。）

## 从源码构建

需要 Flutter 稳定版（本仓库 CI 使用 3.47.5）：

```bash
flutter pub get
dart run build_runner build          # 生成 freezed / 本地化等代码
flutter build windows                # Windows
flutter build apk --split-per-abi    # Android（发布版需自备签名配置）
```

## 上游与致谢

- 本项目基于 [nini22P/iris](https://github.com/nini22P/iris)（作者 [nini22P](https://github.com/nini22P)）；上游原版可在[微软商店](https://apps.microsoft.com/detail/9NML7WNHNRTJ)获取。
- 喜欢本项目的话，也欢迎支持上游作者：[爱发电](https://afdian.com/a/nini22P) / [Ko-fi](https://ko-fi.com/nini22p)。

## 反馈

- 本仓库为个人维护的增强分支。涉及上游原有功能的问题，建议前往[上游仓库 Issues](https://github.com/nini22P/iris/issues)反馈；本分支的改动与修复记录见 [CHANGELOG.md](./CHANGELOG.md)。

## 许可证

本项目采用 MPL-2.0 许可证，详细信息请查看 [LICENSE](./LICENSE) 文件。

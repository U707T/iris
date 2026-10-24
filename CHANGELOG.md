## v2.6.1

### Changelog

* **Seeking no longer fights the decoder.** Dragging used to fire a real seek every 120 ms, so the picture kept jumping and stuttered on slow devices and network sources. Now a drag only moves the preview — zero decoding work — and the picture catches up once your finger rests for 350 ms; releasing lands exactly and resumes. Drag, short-video swipe and both progress bars share this one rule.
* **No more flicker in the seek readout.** The centre chip was rebuilt with a per-frame key, so its contents cross-faded on every frame while dragging. It now only re-renders when the value actually changes, and the delta has a fixed width so the chip does not jitter between `+9s` and `+10s`.
* **Cleaner release.** If the picture already caught up while your finger was resting, releasing no longer seeks a second time (that was the white flash on let-go), and the preview is only dropped after the player's position has actually moved.
* **Double-tap is millisecond-accurate.** It used to go through the second-truncated `forward` / `backward` helpers, so a 5 s step could land 4.2 s away and the two modes read different player instances. Both now seek from the live position with full precision.
* **Volume / brightness keep up.** Platform writes are coalesced (serial, latest value wins) instead of one call per frame, so the level no longer lags behind your finger or floods the platform channel on fast swipes.
* **Tapping the short-video progress bar behaves like the main slider** — pause, land, resume — instead of seeking while playing.

### 更新日志

* **拖动不再和解码器抢资源。** 以前每 120ms 就发一次真实 seek，画面反复跳变，低端机和网络源上直接卡成幻灯片。现在拖动只移动预览值（零解码开销），手指**停住 350ms** 画面才跟上；松手精确落定并续播。画面横滑、短视频横滑、两条进度条共用这一套规则。
* **拖动读数不再闪。** 中央胶囊以前每帧都换 key，导致内容每帧交叉淡入淡出；现在只在数值真正变化时重建，增量也改成固定宽度，`+9s` 到 `+10s` 不会再让胶囊跳一下。
* **松手更干净。** 手指停住时画面已经跳到目标的话，松手不再重复 seek 一次（那一下白闪就是它），预览也改成等播放器位置真的移动之后再收起。
* **双击改成毫秒精度。** 以前走 `forward` / `backward` 的秒级截断，跳 5 秒实际可能只跳 4.2 秒，两个模式读的还是不同实例；现在都从实时位置按毫秒精度落点。
* **音量 / 亮度跟得上手。** 平台写入改为「串行 + 只保留最新值」，不再每帧一次调用，快速滑动时既不会落后于手指，也不会把平台通道打满。
* **短视频进度条点击**改成与主窗口滑块一致（暂停 → 落点 → 续播），不再「播放中跳一下继续播」。

## v2.6.0

### Changelog

* **Unified seek gestures.** The main player and short-video mode now share one gesture layer instead of two divergent implementations. Horizontal drag pauses playback, previews the target position live (120 ms throttled seek), lands exactly where you release and resumes if it was playing — identical in both modes.
* **One threshold everywhere.** An 8 dp dead zone plus a 1.4x dominant-axis ratio decide whether a drag is seeking, volume/brightness or page-turning. Diagonal swipes no longer get captured by the wrong gesture, and short video no longer steals a horizontal step before scrolling to the next clip.
* **Double-tap zones aligned.** Left / right third rewinds / forwards by the configured step (previously the main window used 25% and short video had no on-screen feedback), the middle third plays/pauses (desktop keeps fullscreen). Both modes now show the same centred `±Ns` chip.
* **Live position readout while scrubbing.** The control bar slider, the minimal progress overlay and the short-video footer all read the same preview value, so the time and thumb follow your finger instead of lagging behind the player callback. Scrubbing shows `target / duration  ±delta` in the centre.
* **Volume / brightness rebuilt.** Both now use base value + accumulated offset (200 px = full scale) instead of per-frame deltas, so they no longer drop the first part of the gesture or fall behind on fast swipes; brightness/volume indicators share the same centred chip as seek feedback.
* **Controls no longer disappear mid-scrub.** Auto-hide is suspended while seeking (and re-armed afterwards instead of stopping for good).

### 更新日志

* **滑动快进统一。** 主窗口与短视频模式不再各写一套手势，改为共用同一份实现：横滑即暂停、本地预览实时跟手（120ms 节流 seek）、松手精确落点并在原本播放时续播 —— 两个模式行为完全一致。
* **判定阈值统一。** 8dp 死区 + 1.4 倍主轴优势比决定这次滑动是调进度、调音量亮度还是翻页。斜滑不再被错误的功能抢走，短视频也不会先拖一下进度再翻页。
* **双击分区统一。** 左 / 右 1/3 按设置的步长快退 / 快进（主窗口此前是 25%，短视频此前没有画面提示），中间 1/3 播放暂停（桌面端仍是切全屏）。两个模式都显示同样的居中 `±Ns` 提示。
* **拖动时有实时读数。** 控制栏进度条、极简进度浮层、短视频底部时间读取同一个预览值，时间与滑块跟手而不是等播放器回调；拖动中画面中央显示「目标位置 / 总时长 ±增量」。
* **音量 / 亮度重做。** 改为「基准值 + 累计位移」（200px 满量程），不再丢起手的第一段位移，快速滑动也不会跟不上手；指示器与快进提示共用同一套居中胶囊。
* **拖动时控制栏不再中途消失。** seek 期间暂停自动隐藏，结束后重新计时（而不是就此停摆）。

## v2.5.2

### Changelog

* **Storage fixes.** WebDAV subdirectories and file names containing `#` / `?` now get the correct URL; one unreadable entry no longer fails a whole local folder, and directory stats are read in small concurrent batches; clearing the Android path field no longer crashes, and SAF folders are not blocked by the global storage permission.
* **Responsive control bar.** Controls no longer overflow on narrow phones or tablet-width windows; audio track, storage and fullscreen move into the More menu in the compact layout.
* **Seeking and window state.** Dragging the main progress bar is throttled (120 ms, exact final position on release); the maximize button follows real window events; closing the window flushes the last position / size / maximized state.
* **Persistence hardening.** Settings, queue and history now live in private JSON files (credentials stay in encrypted storage); a failed read is no longer treated as empty data and cannot overwrite the old file; writes are serialized and coalesced; startup waits for stores to load; old data is migrated from encrypted storage automatically.
* **Search, short video and gestures.** Closing search cancels the background scan; short-video page sync, long-press speed restore, scrub lifecycle and touch/mouse detection are fixed; the short-video pool no longer initializes libass.

### 更新日志

* **存储修复。** WebDAV 子目录和含 `#` / `?` 的文件名不再拼错 URL；本地目录里单个坏条目不会让整个文件夹报错，目录信息改为小批量并发读取；Android 清空路径输入不再崩溃，SAF 目录不再被全局存储权限拦住。
* **响应式控制栏。** 窄屏手机 / 平板宽度下按钮不再溢出；紧凑布局把音轨、存储、全屏收进「更多」菜单。
* **进度与窗口。** 主进度条拖动按 120ms 节流（松手补发最终位置）；最大化按钮跟随真实窗口事件；关窗前补存最后的窗口位置 / 大小 / 最大化状态。
* **持久化加固。** 设置、队列、历史迁移到应用私有 JSON 文件（凭据仍在加密存储）；读取失败不再当成空数据覆盖旧文件；写入串行并合并；启动时等待 store 加载完成；旧版数据会自动从加密存储迁移。
* **搜索、短视频与手势。** 关闭搜索会取消后台扫描；短视频程序化翻页、长按倍速恢复、进度拖动生命周期、触摸 / 鼠标判定均已修复；短视频播放器池不再初始化 libass。

## v2.5.1

### Changelog

* **The Dav defaults are prefilled, not read-only.** A new WebDAV connection still starts with `Dav` / `/dav` / `5244` / `admin` / `123456`, but every field is now editable right away — no switch to unlock. An existing connection keeps its saved values
* No other changes.

### 更新日志

* **Dav 默认值改成预填，不再只读。** 新建 WebDAV 时仍会带出 `Dav` / `/dav` / `5244` / `admin` / `123456`，但所有字段一开始就能直接修改，不需要先解锁开关；编辑已有连接仍按保存的值展示
* 本版无其他变化。

## v2.5.0

### Changelog

* **Notch / edge-to-edge top bar.** The title bar, the minimal progress title, the stats overlay and the short-video back button now sit below the status bar / display cutout (`MediaQuery.viewPadding.top`), and Android is allowed to draw into the cutout area (`LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES`). The video itself is untouched and stays centred
* **Control auto-hide is configurable.** Settings → Play now has "Auto-hide controls" (on/off) and "Hide after" (2 / 3 / 5 / 10 / 15 / 30 seconds). Defaults keep the previous behaviour (on, 5 s)
* **WebDAV: built-in Dav profile.** A new WebDAV connection starts with `Dav` / `/dav` / `5244` / `admin` / `123456` filled in and locked; turn "Default Dav profile" off to edit any of them. The host is still yours to fill (the lightning button reads the default gateway). The default password lives in the app — fine for a self-hosted / LAN device, change it for anything reachable from the internet
* No other changes.

### 更新日志

* **刘海 / 全面屏顶部适配。** 标题栏、迷你进度标题、统计 OSD 和短视频返回按钮都会让出状态栏 / 刘海安全区（`MediaQuery.viewPadding.top`）；Android 允许内容画进挖孔区域（`LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES`）。视频画面本身不动，仍然居中
* **控制栏自动隐藏可配置。** 设置 → 播放里新增“自动隐藏控制栏”开关与“隐藏延迟”（2 / 3 / 5 / 10 / 15 / 30 秒）。默认保持原来的行为（开启，5 秒）
* **WebDAV 内置 Dav 配置。** 新建 WebDAV 时默认填好 `Dav` / `/dav` / `5244` / `admin` / `123456` 并锁定；关掉“默认 Dav 配置”开关即可修改任意项。主机仍需你填（小闪电可读网关）。默认密码写在客户端里——自建 / 局域网设备没问题，公网可达的 NAS 请务必改掉
* 本版无其他变化。

## v2.3.5

### Changelog

* **The WebDAV "default gateway" button actually works now.** Android 10+ blocks apps from reading `/proc/net/route`, and `ip route` is usually blocked by SELinux as well, so on Android the button could never fill in the host. It now asks the system through `ConnectivityManager` (the same source the OS uses for the active network's default route), with `/proc/net/route` / `ip route` kept as fallbacks. The added `ACCESS_NETWORK_STATE` is a normal install-time permission: no prompt, no user action
* Windows: `route print` now gets 8 seconds (large routing tables with a VPN, Docker or several NICs could exceed the old 3-second timeout), and a PowerShell `Get-NetRoute` fallback was added
* If the gateway still cannot be read, the dialog now says "enter it manually" instead of just failing silently
* No other changes.

### 更新日志

* **WebDAV 的“读取默认网关”按钮真的能用了。** Android 10+ 禁止应用读 `/proc/net/route`，`ip route` 也基本被 SELinux 拦掉，所以之前 Android 上这个按钮必然失败。现在改为通过系统 `ConnectivityManager` 查询当前网络的默认路由（和系统自己用的是同一份数据），`/proc/net/route` / `ip route` 保留为兜底。新增的 `ACCESS_NETWORK_STATE` 是安装时普通权限，不弹窗、不需要用户操作
* Windows：`route print` 超时从 3 秒放宽到 8 秒（开了 VPN / Docker / 多网卡时路由表大，旧超时可能不够），并增加 PowerShell `Get-NetRoute` 兜底
* 如果仍然读不到，对话框会明确提示“请手动填写”，不再只是静默失败
* 本版无其他变化。

## v2.3.4

### Changelog

* **Desktop: closing the window now saves your position.** Alt+F4, the taskbar close button and the in-app close button all go through one `WM_CLOSE` handler that saves the current playback position before destroying the window. A 30-second autosave (only once playback has advanced 20 seconds) covers crashes and force-kills as well
* **A file that cannot be played now says so.** Opening has a 15-second timeout and every file switch invalidates the previous loader session — a slow network source can no longer land on top of the file you just switched to. Timeouts and decode errors show a card with the file name and a Retry button, in normal and short-video mode alike
* **Resume works reliably again.** The resume decision waits for the history to be read from disk and is made once per file; `duration` changes during opening no longer drag you back to an old position. Switching files or stopping re-arms it
* **Android: mixed local + SAF queues are saved.** A queue containing `content://` entries used to stop being persisted entirely; now only the session-only SAF entries are stripped (the current index is remapped), and the rest survives a restart. Deleting the last local item no longer brings it back on the next launch
* **"Open with" / command-line auto-play race fixed.** The app state and the play queue load independently; a launch flag is now shared, so a file opened from the command line or an Intent starts playing regardless of which store finished first
* **Drag and drop across folders.** Dropping several files builds the queue from the dropped list itself (duplicates and non-media files filtered); previously only the first file's folder was scanned, the other files were dropped silently, and a path mismatch could leave a queue that played nothing. Relative paths (`iris movie.mp4`) now work too
* **Volume fixes.** "Muted + volume 0" now unmutes and restores 80% in one click; dragging the volume slider no longer writes the whole encrypted app state on every frame (once on release), and fast mouse-wheel steps are no longer lost (coalesced 400 ms write)
* **The control bar no longer vanishes while you aim at it.** The 5-second auto-hide honours pointer hover on the title / control bars and restarts the timer when the pointer leaves
* **Seeking while dragging is throttled** (120 ms, exact final position on release) in both the main player and short-video mode, instead of sending dozens of mpv seek commands per drag
* **Queue order is consistent.** The file picker, drag and drop and the command line now use the same sort by name / size / modified time as the file browser
* **WebDAV: new "default gateway" shortcut.** A small lightning button next to the Host field fills in the router's IP (Windows `route print`, Linux / Android `ip route` / `/proc/net/route`, macOS `route -n get default`). If it cannot be read, the dialog says so instead of guessing
* Short video: the playback-stats OSD is no longer offered there (it had no data source); programmatic page jumps no longer commit intermediate pages
* No other changes.

### 更新日志

* **桌面端关窗会保存进度了。** Alt+F4、任务栏关闭和自绘标题栏的 X 现在走同一个 `WM_CLOSE` 处理：先保存当前位置，再销毁窗口。另加 30 秒自动保存（位置前进超过 20 秒才写），崩溃 / 被强杀也能兜住
* **播不了的文件会明确报错。** 打开加了 15 秒超时，切文件会作废上一轮装载 —— 慢速网络源不会再“晚到”并顶掉你刚切到的文件。超时 / 解码失败会显示文件名片 + 重试按钮，普通模式和短视频模式都有
* **续播恢复可靠了。** 恢复判断会等历史记录读盘完成，且每个文件只决策一次；打开期间 `duration` 多次变化不会再把你拽回旧位置。切文件 / 停止后会重新允许恢复
* **Android：本地 + SAF 混合队列会保存了。** 以前队列里只要有一条 `content://` 就整份不落盘；现在只剔除重启后打不开的 SAF 条目（当前索引自动映射），其余照常保留。删掉最后一条本地条目也不会在下次启动时“复活”
* **“用其他应用打开” / 命令行的自动播放竞态修复。** 设置与播放队列是两个独立异步加载的 store，现在共用一个启动标记：从命令行或 Intent 打开文件，不管哪个先加载完都会自动播
* **跨文件夹拖放。** 拖入多个文件时直接用拖入列表建队列（去重、过滤非媒体）；以前只扫第一个文件所在目录，其他文件被静默丢弃，路径对不上时还会出现“队列有内容但什么都不播”。相对路径（`iris movie.mp4`）也能用了
* **音量修复。** “静音 + 音量 0”点一次就取消静音并恢复到 80%；拖动音量滑杆不再每帧把整份加密状态写盘（松手写一次）；快速滚轮不再丢步（400ms 合并写）
* **鼠标停在控制栏上时不会被自动隐藏了。** 5 秒自动隐藏会看指针是否停在标题栏 / 控制栏上，指针离开时重新计时
* **拖动进度条时 seek 节流**（120ms，松手补最终位置），主界面和短视频模式一致，不再一次拖动发几十条 mpv seek
* **队列顺序统一。** 文件选择器、拖放和命令行现在都跟文件浏览器用同一套排序（名称 / 大小 / 修改时间）
* **WebDAV：新增“默认网关”快捷按钮。** 主机框右侧的小闪电会自动填入路由器 IP（Windows `route print`、Linux / Android `ip route` / `/proc/net/route`、macOS `route -n get default`）；读不到就在输入框下方提示，不瞎猜
* 短视频：不再提供播放统计 OSD（那边没有数据源）；程序化翻页不会再提交中间页
* 本版无其他变化。

## v2.3.3

### Changelog

* **Much smaller APK: 65.6 MB → 35.4 MB (-46%) on arm64.** Three things were carrying the weight: a 16.5 MB CJK subtitle font (21% of the package), a second playback engine (FVP: `libffmpeg` + `libmdk` + `libass`, 12.2 MB) and a duplicated copy of every dependency's licence text. All three are gone; nothing that you asked to keep was touched
* **Subtitles are removed.** The bundled Noto CJK font, the subtitle panel, sidecar `.srt/.ass` scanning, the "burn subtitles into the screenshot" option, the preferred-subtitle-language setting and the automatic selection of embedded subtitle tracks are gone, and `libass` subtitle rendering plus the Flutter subtitle layer are switched off — so a video with embedded subs no longer paints a row of tofu boxes. The `S` shortcut and the control-bar button now open audio tracks only. Startup also no longer copies 16.5 MB from assets to the app directory on first launch
* **FTP is removed; WebDAV is unchanged.** This also drops the bundled `media_stream` local HTTP server (the app no longer starts a background streaming server during launch), the patched `pure_ftp` copy, and `shelf`/`shelf_router`. Save-side migration: FTP storages are dropped from the saved storage list, and queue / history entries pointing at FTP files are filtered out on load (so the rest of the queue and history still restore instead of being discarded wholesale)
* **FVP backend removed; Media Kit (libmpv/FFmpeg) is the only player.** Short video mode never used FVP (no player pool there), and keeping it meant shipping a patched in-tree copy just to dodge a Windows start-up crash. Also removed: the "player backend" setting, the `video_player` / `wakelock_plus` dependencies and the `third_party/fvp` patch. Windows package: 44.3 MB → 35.6 MB (installer 33.1 → 26.6 MB)
* Licence page now uses Flutter's own `LicenseRegistry` (the same NOTICES that were already shipped): the 619 KB, 12k-line `oss_licenses.dart` is gone
* UI text uses the system font again (Android: Noto Sans CJK, Windows: Microsoft YaHei): `google_fonts` used to download Noto Sans SC over the network at runtime, a hidden start-up request
* Removed the unused `cupertino_icons` package and the Gradle task that downloaded the subtitle font at build time
* Unchanged: video playback and resume, short video mode (pool, preload, swipe, double-tap seek, volume button), WebDAV, play queue / shuffle / repeat, history, screenshots, rotation / flip, playback stats, search
* No other changes.

### 更新日志

* **安装包小了一半：arm64 从 65.6MB 降到 35.4MB（-46%）。** 重量来自三处：16.5MB 的中日韩字幕字体（占包体 21%）、第二套播放内核（FVP：`libffmpeg` + `libmdk` + `libass`，12.2MB）、以及一份重复打包的依赖许可文本。三处全部移除；你要保留的功能一个没动
* **移除字幕功能。** 内置 Noto CJK 字体、字幕面板、同目录 `.srt/.ass` 扫描、"截图烧入字幕"选项、首选字幕语言设置、内嵌字幕自动选中全部删除；同时关闭了 libass 字幕渲染与 Flutter 字幕层——带内嵌字幕的视频不会再盖一层方块。`S` 快捷键与控制栏按钮现在只打开音轨。首次启动也不再从 assets 复制 16.5MB 字体到应用目录
* **移除 FTP（WebDAV 保持不变）。** 顺带移除内置的 `media_stream` 本地 HTTP 服务（启动时不再起后台推流服务器）、打补丁的 `pure_ftp`、`shelf`/`shelf_router`。存档迁移：保存过的 FTP 存储会从列表丢弃；队列 / 历史里指向 FTP 文件的条目在加载时被过滤掉（其余队列和历史照常恢复，不会整份丢掉）
* **移除 FVP 后端，只保留 Media Kit（libmpv/FFmpeg）。** 短视频模式本来就没用过 FVP（那边没有预载池），留着它还得在仓库里维护一份打补丁的副本才能避开 Windows 启动崩溃。一并移除："播放器后端"设置、`video_player` / `wakelock_plus` 依赖、`third_party/fvp` 补丁。Windows 包：44.3MB → 35.6MB（安装器 33.1 → 26.6MB）
* 许可页改用 Flutter 自带的 `LicenseRegistry`（就是构建时本来就打包的 NOTICES）：删掉了 619KB、1.2 万行的 `oss_licenses.dart`
* 界面文字改回系统字体（Android：Noto Sans CJK；Windows：微软雅黑）：`google_fonts` 以前会在运行时从网络下载 Noto Sans SC，是一个隐藏的启动请求
* 移除未被引用的 `cupertino_icons`，以及 Gradle 里构建期下载字幕字体的步骤
* 保持不变：视频播放与续播、短视频模式（池 / 预载 / 滑动 / 双击快进 / 音量按钮）、WebDAV、播放队列与随机循环、历史、截图、旋转 / 翻转、播放统计、搜索
* 本版无其他变化。

## v2.3.3-rc.2

### Changelog

* **The FVP backend is gone; Media Kit is now the only player.** FVP (mdk-sdk) was an optional second backend, but short video mode never used it (no player pool there — it fell back to a stripped-down single-video path), it required a patched in-tree copy to avoid a Windows start-up crash, and it pulled in `video_player` + `wakelock_plus`. Videos that used to need "switch to FVP" can be played from the Media Kit (libmpv/FFmpeg) backend; if a rare file still fails, FVP can be brought back as an optional build later
* Removed together with it: `libffmpeg` (8.3 MB) / `libmdk` (2.3 MB) / `libass` (1.5 MB) on Android, `ffmpeg-9.dll` / `mdk.dll` / `libass.dll` (8.3 MB) on Windows, the "player backend" setting, `wp`-style per-backend branches in the video view / short video fallback / audio track list, and the `video_player` / `wakelock_plus` dependencies
* Windows also loses the in-tree `third_party/fvp` patch, so there is no longer a patched C++ dependency to maintain
* Everything you asked to keep is untouched: video playback and resume, short video mode (pool / preload / swipe / double-tap seek / volume button), WebDAV, queue, history, screenshots, rotation and stats
* Expected APK size: about 49.9 MB → 37.7 MB on arm64 (65.6 MB before v2.3.3)
* No other changes.

### 更新日志

* **移除 FVP 后端，只保留 Media Kit。** FVP（mdk-sdk）原本是可选第二后端，但短视频模式从来没用上它（没有预载池，只能回退到残缺的单条模式），还得在仓库里维护一份打补丁的副本才能避开 Windows 启动崩溃，并且额外拖着 `video_player` + `wakelock_plus` 两个依赖。以前"切到 FVP 才能播"的文件请用 Media Kit（libmpv/FFmpeg）；真遇到极少数播不了的文件，以后可以作为可选构建再加回来
* 一并移除：Android 的 `libffmpeg`（8.3MB）/ `libmdk`（2.3MB）/ `libass`（1.5MB），Windows 的 `ffmpeg-9.dll` / `mdk.dll` / `libass.dll`（8.3MB），"播放器后端"设置项，视频画面 / 短视频回退 / 音轨列表里的分支代码，以及 `video_player` / `wakelock_plus` 依赖
* Windows 侧也不再需要 `third_party/fvp` 那份 C++ 补丁，少一个需要跟上游同步的维护点
* 你要保留的部分一律未动：视频播放与续播、短视频模式（池 / 预载 / 滑动 / 双击快进 / 音量按钮）、WebDAV、播放队列、历史、截图、旋转、播放统计
* 预期包体：arm64 约 49.9MB → 37.7MB（v2.3.3 之前是 65.6MB）
* 本版无其他变化。

## v2.3.3-rc.1

### Changelog

* **The APK is a lot smaller: subtitles are gone.** IRIS used to bundle a 16.5 MB CJK font (21% of the APK) purely so libass could draw Chinese/Japanese subtitles, and copied it to the app directory on first launch. Subtitle support (embedded and sidecar) has been removed together with that font, the subtitle picker, the sidecar `.srt/.ass` scanning, the "burn subtitles into screenshot" option and the preferred-subtitle-language setting. Videos now always play without a subtitle track (no more auto-selecting an embedded track). The `S` shortcut and the control-bar button now open audio tracks only
* **FTP support has been removed** (WebDAV is unchanged). This also drops the bundled `media_stream` local HTTP server, so the app no longer starts a background streaming server at launch, plus the patched `pure_ftp` copy. A previously saved FTP storage is dropped from the saved list on first launch; local / WebDAV storages and favourites are unaffected
* Licence page now comes from Flutter's own `LicenseRegistry` (the same NOTICES that were already shipped): the 619 KB, 12k-line `oss_licenses.dart` is gone
* UI text uses the system font again: `google_fonts` used to download Noto Sans SC from the network at runtime, which was a hidden startup request; the font now follows the system (Noto Sans CJK on Android, Microsoft YaHei on Windows)
* Removed the unused `cupertino_icons` package (its font was shipped but never referenced) and the build-time font download step in Gradle
* Unchanged: video playback (Media Kit + FVP backends), short video mode, gestures, play queue, history/resume, screenshots, rotation, stats, search and WebDAV streaming
* Expected APK size: about 62.6 MiB → 48 MiB on arm64
* No other changes.

### 更新日志

* **安装包明显变小：字幕功能已移除。** 以前为了让 libass 能画中日文字幕，包里内置了一份 16.5MB 的中日韩字体（占 APK 21%），首次启动还会复制到应用目录。现在字幕支持（内嵌 + 外挂）连同这份字体一起移除：字幕选择面板、同目录 `.srt/.ass` 扫描、"截图烧入字幕"选项、首选字幕语言设置都已删除，视频一律不带字幕轨播放（不再自动选中内嵌字幕）。`S` 快捷键与控制栏按钮现在只打开音轨
* **移除 FTP 支持**（WebDAV 保持不变）。顺带移除了内置的 `media_stream` 本地 HTTP 服务——应用启动时不再起后台推流服务器，也去掉了打补丁的 `pure_ftp`。之前保存过的 FTP 存储在首次启动时会从列表里自动丢弃；本地存储、WebDAV 与收藏不受影响
* 许可页改用 Flutter 自带的 `LicenseRegistry`（就是构建时本来就打包的 NOTICES）：删掉了 619KB、1.2 万行的 `oss_licenses.dart`
* 界面文字改回系统字体：`google_fonts` 以前会在运行时从网络下载 Noto Sans SC（一个隐藏的启动请求），现在跟随系统（Android 是 Noto Sans CJK，Windows 是微软雅黑）
* 移除未被引用的 `cupertino_icons`（字体一直在包里但代码从未使用），以及 Gradle 里构建期下载字体的步骤
* 保持不变：视频播放（Media Kit + FVP 双后端）、短视频模式、手势、播放队列、历史/续播、截图、旋转、播放统计、搜索、WebDAV 播放
* 预期包体：arm64 约 62.6 MiB → 48 MiB
* 本版无其他变化。

## v2.3.2

### Changelog

* **Queue navigation no longer crashes on an empty queue**: pressing Ctrl + ← / → , the media keys, or the previous / next buttons after the queue has been emptied used to throw a `StateError` (`.first` / `.last` on an empty list) straight out of the key handler. It now does nothing
* **Auto-play after a video ends can no longer run off the end of the queue**: if the last entry was deleted while it was playing, finishing it read `playQueue[0]` on an empty list. The "what plays next" rule (single-item repeat / loop all / stop at the end) now lives in one shared helper used by both the Media Kit and the FVP backend, so the two cannot drift apart again. One behaviour fix comes with it: with "repeat all" and a single-file queue the video now really replays (it used to stay stopped on the last frame)
* **Playback progress is restored only once per file**: `duration` can change several times while a video is opening (probing, resolution changes), and each change re-ran the resume logic, dragging you back to the old position. Resuming now happens on the first known duration only; switching files / stopping re-arms it
* **Update check has a timeout and tolerates odd version tags**: the request used to hang forever on a broken network (the row stayed on "check update"), and a tag such as `v2.3.0-rc.1` threw a `FormatException`. The request now times out after 10 s, and version parsing accepts a `v` prefix, a `-rc.1` pre-release suffix and a `+25` build number. A pre-release is never reported as newer than the same release, and a release without a build for your platform is no longer an error
* **Storage permission is requested only once**: on Android 10 and older, choosing "don't ask again" made the old code call itself recursively forever (hang / stack overflow). The result is now returned to the caller so the file panel can offer the "go to settings" path
* **FTP: 10 s connection timeout, and a failure is no longer an empty folder**: an unreachable server used to leave the file panel spinning for 30 s, then show an empty directory. It now times out quickly and surfaces as "unable to fetch files"; the connection is also closed on failure instead of leaking the socket
* **Mute state is now written to disk**: `toggleMute` fired the save without awaiting it, so the state was occasionally lost
* **CI now runs `flutter analyze` and `flutter test`** before building (it used to build only), and the removed `--delete-conflicting-outputs` flag is gone from the workflow
* No startup / launch-path changes in this release: it is pure logic, permissions and networking
* No other changes.

### 更新日志

* **空队列时上一条 / 下一条不再崩溃**：队列被清空后按 Ctrl + ←/→、媒体键或控制栏的上一条 / 下一条，会在按键回调里直接抛 `StateError`（对空列表取 `.first` / `.last`）。现在什么都不做
* **视频播完自动连播不再越界**：播放中把最后一条删掉，播完时会对空列表取 `playQueue[0]`。连播规则（单条循环 / 列表循环 / 播到末尾停下）现在收进一个公共函数，Media Kit 与 FVP 两个后端共用，不会再改一边漏一边。顺带修一个行为：列表循环 + 队列只剩一条时现在会真正重播（以前会停在最后一帧）
* **播放进度每个文件只恢复一次**：打开视频期间 `duration` 会变化多次（探测、变分辨率），每次变化都会重跑恢复逻辑，把已经看到一半的你拽回旧进度。现在只在首次拿到时长时恢复；切歌 / 停止后会重新允许恢复
* **检查更新加超时，版本号容错**：网络异常时请求以前会一直挂着（界面停在「检查更新」），`v2.3.0-rc.1` 这类 tag 会抛 `FormatException`。现在请求 10 秒超时；版本解析兼容 `v` 前缀、`-rc.1` 预发布后缀与 `+25` 构建号。预发布不会被当成比同号正式版更新，发布里没有对应平台的安装包也不再算错误
* **存储权限只申请一次**：Android 10 及以下选择「不再询问」时，旧实现会无限递归调用自己（卡死 / 爆栈）。现在把结果返回给调用方，由文件面板引导去系统设置
* **FTP：连接超时 10 秒，失败不再伪装成空文件夹**：服务器不可达时以前会转圈 30 秒再显示一个空目录。现在很快超时并显示「无法获取文件」；失败时也会断开连接，不再泄漏 socket
* **静音状态会落盘**：`toggleMute` 调用 `save` 时没有 await，导致静音状态偶尔丢失
* **CI 增加 `flutter analyze` + `flutter test`**（此前只构建不测试），并清掉了工作流里已被移除的 `--delete-conflicting-outputs` 参数
* 本版**不含任何启动链路改动**：只有纯逻辑、权限与网络
* 本版无其他变化。

## v2.3.1

### Changelog

* **Rolled back every change from 2.4.0 and 2.4.1**: those releases introduced a launch regression (a black screen) on some devices. This build restores the exact v2.3.0 behaviour — none of the 2.4.x startup, permission, player-UI or networking changes are included
* Nothing else changed compared with v2.3.0. The version code is higher (25) than 2.4.1's, so this build can be installed directly over 2.4.x

### 更新日志

* **已撤回 2.4.0 / 2.4.1 的全部改动**：这两个版本在部分设备上引入了启动黑屏。本版本恢复到 v2.3.0 的完整行为，不包含任何 2.4.x 的启动、权限、播放器界面或网络改动
* 与 v2.3.0 相比没有其他变化。版本号（25）高于 2.4.1，可直接覆盖安装 2.4.x

## v2.3.0

### Changelog

* **Windows: the accessibility workaround for the engine crash (flutter/flutter#175041) is now built in and enabled by default** — Windows builds start normally out of the box, no environment variable or command-line flag needed. The trade-off is unchanged: while the workaround is active, IRIS turns its own Windows accessibility integration off, so screen readers cannot read the app. If you need accessibility tools to work (and accept the crash risk), opt out with `IRIS_ENABLE_WINDOWS_A11Y=1` or `--enable-windows-a11y`; the old `IRIS_DISABLE_WINDOWS_A11Y=1` / `--disable-windows-a11y` are still accepted. The README troubleshooting section has been updated
* **Short video mode: double-tap seek feedback** — double-tapping the right / left quarter now shows a brief "±Ns" pill in the centre of the picture (it reads the configured seek step, e.g. 5 s), so you can see how far the jump went; the long-press speed effect is unchanged
* Short video mode fixes: a queue change while a video was still loading could let stale loading work land on a reassigned slot (occasionally playing the old video briefly or hiding the loading spinner early) — that race is closed; fine-tuning the device volume with the mouse wheel no longer loses steps when several wheel events arrive at once; and the press-and-hold mute gesture now tolerates a bit of natural finger movement (8 px) instead of treating it as a volume slide
* **Player: the volume popover no longer swallows the first scroll-up while muted** — it now unmutes and raises the volume in one step (before, the first scroll unmuted but left the volume at 0, so nothing could be heard)
* Keyboard: Ctrl + C (stop) now clears auto-play exactly like the stop button; holding the volume arrow keys no longer writes to disk on every key repeat (the final value is saved when the key is released)
* Stability: the playback history is capped at 300 entries (it used to grow forever, making every progress save slower); the fullscreen toggle now honours the requested state instead of always flipping; the folder search dialog discards stale results and no longer touches a closed dialog; opening a file whose path is not in the listing no longer throws; audio cover lookup handles storage errors; and the first-frame wait no longer overrides a pause or a file switch made while the video was still opening
* Structure (no behaviour change): the short video screen, the playback control bar and the file browser were split from giant single-widget files into focused modules (wheel / scrub / volume / feed widgets; layout + button modules; file list row + bottom bar). All unit and widget tests pass
* No other changes.

### 更新日志

* **Windows：引擎崩溃（flutter/flutter#175041）的无障碍兼容规避已内置、默认生效** —— Windows 版开箱即用，不再需要任何环境变量或命令行参数。代价照旧：规避生效时 IRIS 会关闭自身的 Windows 无障碍集成，屏幕阅读器无法读取应用。如你确实需要读屏、且愿自担崩溃风险，可用 `IRIS_ENABLE_WINDOWS_A11Y=1` 或 `--enable-windows-a11y` 显式退出；旧的 `IRIS_DISABLE_WINDOWS_A11Y=1` / `--disable-windows-a11y` 仍然兼容。README 故障排查一节已同步更新
* **短视频模式：双击快进 / 快退反馈** —— 双击画面右侧 / 左侧四分之一区域时，画面中央短暂显示「±Ns」提示（取设置里的实际步长，如 5s），跳了多少一目了然；长按倍速光效保持不变
* 短视频模式修复：装载进行中队列发生变化时，过期的异步装载可能落到已被重新分配的槽位上（偶发播放到旧视频 / 加载指示提前熄灭）——该竞态已修复；鼠标滚轮微调设备音量在连续快速滚动时不再丢步；按住音量按钮的静音手势现在容忍几像素的自然抖动（滑动判定 8px），不再被误判成滑动
* **播放器：静音时音量浮层上滚不再"第一步白滚"** —— 现在一步到位：取消静音并同时加音量（此前第一格只取消静音、音量仍是 0）
* 键盘：Ctrl + C（停止）现在与控制栏停止按钮一致，会清除自动播放标记；按住音量方向键不再每个按键重复都写一次磁盘（松开时落盘最终值）
* 稳定性：播放历史上限 300 条（此前无限增长，每次保存进度越来越慢）；全屏开关改为按传入的目标值设置而不是无条件取反；文件夹搜索对话框会丢弃过期结果、关闭后不再写入状态；打开不在列表中的文件不再抛异常；音频封面查找处理存储错误；首帧等待不再覆盖用户在打开期间做出的暂停 / 切歌操作
* 结构（无行为变化）：短视频界面、播放控制栏、文件浏览面板从单个巨型组件拆分为职责单一的小模块（滚轮 / 拖动 / 音量 / 画面组件；布局 + 按钮模块；文件行 + 底部工具条）。全部单元 / 组件测试通过
* 本版无其他变化。

## v2.2.0

### Changelog

* **Long-press speed-up** now shows the same effect everywhere: a soft white light streak breathing on the left and the right edge of the picture, in the normal player and in short video mode — the box with the speed number in the middle of the screen is gone, the centre of the picture stays clean. The effect lives in one shared widget (`lib/widgets/speed_boost_effect.dart`) instead of two copies, and its animation stops while hidden
* **Short video mode volume button** (added in 2.1.0) was reworked: it sits at the top of the right-hand action column (above the play / pause button), and it now adjusts the **device volume** (the absolute volume the hardware volume keys change) instead of the player's software volume, exactly like the up / down drag in the normal player. It also reacts much faster: the long press is recognised after 0.1 s (was 0.5 s), the level is written straight to the system (no batching through the player), the current volume shows up as soon as you hold the button, and sliding is 2 px per 1 %. Tapping still only mutes IRIS itself, and the system volume panel stays hidden while adjusting
* **Fixed videos starting with sound but a black picture** ("开局黑屏"): the player now opens videos paused and waits for the first frame to be ready before playback starts, so audio and picture appear together. Short video mode also decodes the first frame of the preloaded neighbours, so swiping to the next video shows a picture right away
* **Shuffle rework**: the random order is regenerated every time shuffle is switched on (and the file order is restored when it is switched off), and the queue is re-shuffled on launch when shuffle is enabled, so every start of the app plays a fresh order — the whole list is played through in random order, with the current video kept first. Both the control-bar button and Ctrl + X use the same code path now
* Stability: waiting for the first frame is capped by a timeout so a video can never stall the player; shuffle / queue sorting handle empty, single-item and unknown-index queues safely
* No other changes.

### 更新日志

* **长按倍速动效统一**：主播放界面与短视频模式都改成画面左右两侧各一道呼吸的白色光带，画面中央的倍速提示方块去掉，中央区域保持干净。动效抽成一个公共组件（`lib/widgets/speed_boost_effect.dart`），两处共用、不再各写一套，隐藏时动画自动停掉
* **短视频模式音量按钮**（2.1.0 新增）重做：位置移到右侧操作栏最上方（暂停按钮之上）；改为调节**设备音量**（绝对音量，就是手机音量键看到的那个），与主界面上下拖动完全一致；响应也更快——长按识别 0.1s（原 0.5s）、音量直写系统（不再经播放器批量写入）、一按住就显示当前音量、滑动灵敏度 2px = 1%。点击仍然只静音 IRIS 自己，调节期间不弹系统音量条
* **修复"开局有声音但画面黑着"**：视频现在先以暂停方式打开，等首帧就绪后再开始播放，音画一起出现；短视频模式还会把预载的上一条 / 下一条先解出首帧，滑过去立刻有画面
* **随机播放机制重做**：每次打开随机都会**重新洗牌**（关闭时恢复文件原始顺序），启动应用时若随机开着也会重洗一次，因此每次打开应用都是新的顺序——按这份顺序把整个列表播完，当前这条始终排在最前。控制栏按钮与 Ctrl + X 现在走同一套逻辑
* 稳定性：等待首帧带超时兜底，个别视频不会把播放卡住；随机 / 队列排序对空队列、单条队列、下标不存在等情况都做了保护
* 本版无其他变化。

## v2.2.0-rc.2

### Changelog

* Short video mode: the volume button now adjusts the **device volume** — the absolute volume you see with the hardware volume keys — instead of the player's own software volume, so it behaves exactly like the up / down drag in the normal player. Tap still only mutes IRIS itself (other apps keep playing), and starting to slide while IRIS is muted unmutes it first so the change is audible
* Sliding now reacts much faster: the device volume is written straight to the system (no more 100 ms batching through the player), the current device volume appears as soon as the long press is recognised (no waiting for the first movement), and the sensitivity matches the normal player's drag (2 px = 1%)
* The system volume panel stays hidden while adjusting (IRIS shows its own indicator) and is restored afterwards / when leaving the mode
* Desktop: scrolling the wheel over the button fine-tunes the device volume as well
* No other changes.
* This is a release candidate (RC) build for testing before the next stable release.

### 更新日志

* 短视频模式：音量按钮改为调节**设备音量**（绝对音量，就是手机音量键看到的那个），不再改播放器自身的软件音量——手感和行为与主界面上下拖动完全一致。点击仍然只静音 IRIS 自己（不影响其他应用）；静音状态下开始滑动会先自动取消静音，否则调了也听不到
* 滑动明显更跟手：设备音量直写系统（不再经播放器 100ms 批量写入），长按一识别就显示当前设备音量（不用等第一次滑动），灵敏度也与主界面上下拖动对齐（2px = 1%）
* 调节期间不弹系统音量条（IRIS 自己已有指示器），结束调节 / 退出模式后恢复
* 桌面端：指针悬停在按钮上滚轮同样改为微调设备音量
* 本版无其他变化。
* 本版本为候选发布版（RC），用于正式版发布前的测试验证

## v2.2.0-rc.1

### Changelog

* Long-press speed-up now uses the same effect in the normal player and in short video mode: a soft white light streak breathing on the left and the right edge of the picture, instead of the box with the speed number in the middle of the screen. The effect is one shared widget (`lib/widgets/speed_boost_effect.dart`), so both screens stay in sync, and the centre of the picture is left clean. Nothing else about the gesture changed (long-press to speed up, release to go back to the normal rate)
* Short video mode: the volume button moved up to the top of the right-hand action column (above the play / pause button) — higher up in the bottom-right corner, clear of the bottom info bar. Tap is still mute / unmute, hold and slide up / down still adjusts the volume
* Short video mode: holding the volume button now takes over the gesture after 0.1 s instead of 0.5 s, so the volume starts following your finger much sooner; holding without sliding still counts as a tap (mute / unmute), and a normal tap keeps working as before
* No other changes.
* This is a release candidate (RC) build for testing before the next stable release.

### 更新日志

* 长按倍速动效：主播放界面与短视频模式改为同一套动效——画面左右两侧各一道呼吸的白色光带，取代原先画面中央的倍速提示方块；动效抽成一个公共组件（`lib/widgets/speed_boost_effect.dart`），两处共用、不再各写一套，画面中央也保持干净。手势本身没有任何变化（长按加速、松手恢复原速）
* 短视频模式：音量按钮上移到右侧操作栏最上方（暂停按钮之上），即右下角更靠上的位置，不再贴着底部信息栏。点击仍是静音 / 取消静音，按住后上下滑动仍是调音量
* 短视频模式：按住音量按钮的识别时间由 0.5s 缩短到 0.1s，音量明显更跟手；按住不滑动松手仍算点击（静音 / 取消静音），普通点击与之前一致
* 本版无其他变化。
* 本版本为候选发布版（RC），用于正式版发布前的测试验证

## v2.1.0

### Changelog

* Short video mode: new volume button in the right-hand action column (below the screenshot button)
  * Long-press it and slide up / down to adjust the volume — this only works while the button itself is held, so swiping the feed, tapping to pause, double-tap seeking, dragging to scrub and the long-press speed-up all keep working as before; a level indicator appears in the middle of the screen while adjusting
  * Tap it to mute / unmute (tapping it at 0% restores 80%); the icon follows the current level and the muted state
  * Adjusting the volume while muted automatically unmutes, and the value is written to the settings when you let go
  * Desktop: scrolling the wheel over the button fine-tunes the volume instead of switching videos
* No other changes.

### 更新日志

* 短视频模式：右侧操作栏（截图按钮下方）新增音量按钮
  * 长按按钮后上下滑动即可调节音量——仅在按住按钮时生效，滑动翻页、点击暂停、双击快进、横向拖动快进与长按倍速等原有手势完全不受影响；调节时画面中央显示音量指示
  * 点击按钮 = 静音 / 取消静音（音量为 0 时恢复到 80），图标跟随当前音量与静音状态
  * 静音状态下调节音量会自动取消静音，松手后写入设置
  * 桌面端：指针悬停在按钮上滚动滚轮可微调音量（不再翻页）
* 本版无其他变化。

## v2.0.3

### Changelog

* Short video mode: fixed the picture being displayed with a wrong aspect ratio (e.g. a square or squashed frame) which could appear after entering the mode or after switching videos, and only went away after re-entering the mode or another switch. Root cause: each video is opened in a freshly created player of the pool, and the player's video output (texture + surface size) is created asynchronously in parallel with the media open — when the media finished opening first, media_kit's surface-size sync was lost and the picture stayed at the initial 1x1 size. The pool now waits for the video output before opening a video, and additionally re-syncs the surface size once after loading and once right before a video is shown (idempotent, Android only)
* Fixed both modes playing sound at the same time when switching between the normal and short video mode quickly (e.g. tapping a video and immediately entering short video mode): the outgoing player is now explicitly silenced before the mode is switched — its disposal is asynchronous, so it could keep playing while the other mode had already started. The short video pool also opens videos paused and starts playback only after the load completes, so leaving the mode while a video is still loading can no longer produce sound
* Short video mode: subtitles are no longer rendered (the subtitle track is disabled, saving decoding/rendering work)
* Short video mode: scrubbing no longer reads a stale playback state captured at build time — pausing first and then dragging to seek could resume playback unexpectedly (or not resume at all)
* Stability: all fire-and-forget player commands (pause / stop / dispose / seek) are now guarded, so a player that is being disposed can't raise an unhandled error
* No other changes.

### 更新日志

* 短视频模式：修复画面比例异常（例如变成方形 / 被拉伸）——进入模式或切换视频后可能出现，重进模式或再切一条才恢复。根因：池内每个视频都用新建的播放器打开，而播放器的视频输出（纹理 / 画面尺寸）与视频打开是并行初始化的；视频先打开时 media_kit 的画面尺寸同步会丢失，画面一直停留在初始的 1x1 尺寸。现在池内会等视频输出就绪再打开视频，并在装载完成后、视频即将展示时各补一次尺寸同步（幂等，仅 Android）
* 修复快速切换普通模式 / 短视频模式时两个播放器同时出声（例如刚点开视频就进短视频模式）：切换前会先显式静音即将被替换的播放器——它的销毁是异步的，否则会在新模式开始播放后还在出声；短视频池也改为"先暂停打开、装载完成后再播放"，装载途中退出模式不会再出声
* 短视频模式：不再显示字幕（关闭字幕轨，省去字幕解码 / 渲染开销）
* 短视频模式：进度拖动不再读取构建时捕获的过期播放状态——先暂停再拖动快进时，松手可能会意外恢复（或不恢复）播放
* 稳定性：所有"发后不管"的播放器命令（暂停 / 停止 / 销毁 / 跳转）都做了保护，播放器正在销毁时不会再抛出未处理的错误
* 本版无其他变化。

## v2.0.2

### Changelog

* Short video mode: mouse-wheel switching is now robust on high-resolution wheels and remote-desktop sessions — small/partial wheel deltas (which these devices and tools send instead of full notches) are accumulated and switch once a threshold is reached, instead of being ignored; standard wheels behave exactly as before (one notch = one switch)
* No other changes.

### 更新日志

* 短视频模式：鼠标滚轮切换现在兼容高精度滚轮与远程桌面——这类设备/工具会把一个滚轮刻度拆成许多小增量发送，此前会被直接忽略（表现为滚轮完全无反应）；现在会累积到阈值后切换，标准滚轮行为与之前完全一致（一格 = 一次切换）
* 本版无其他变化。

## v2.0.1

### Changelog

* Workaround for a Windows crash (0xC0000005) that could happen right after launch or during the first interactions: Flutter's Windows engine has a known accessibility-bridge crash (flutter/flutter#175041, see also #192689) that is triggered when a UI Automation client — remote-desktop tools such as Chrome Remote Desktop, screen readers, automation utilities — enumerates the window while the app is still starting. This cannot be fixed from inside the app, so this release adds an opt-in compatibility switch that turns the app's Windows accessibility integration off, which avoids the crash (the same approach was verified by other affected apps; see the upstream issue).
  * Turn it on with the environment variable `IRIS_DISABLE_WINDOWS_A11Y=1` or the command-line argument `--disable-windows-a11y` (default: off).
  * Trade-off: while enabled, screen readers cannot see IRIS. It is meant for the machines that hit this crash; machines that never crash keep full accessibility. The switch will be removed once Flutter ships the engine fix (flutter/flutter#190903).
* Nothing else changed in this release.

### 更新日志

* 修复 Windows 端启动阶段 / 首次操作时的闪退（0xC0000005）：这是 Flutter Windows 引擎的已知无障碍桥崩溃（flutter/flutter#175041，另见 #192689）——当 UI 自动化客户端（远程桌面工具如 Chrome Remote Desktop、读屏软件、自动化工具等）在应用启动期间枚举窗口元素时触发。该问题无法在应用内直接修复，因此本版新增一个**可选**兼容开关：开启后关闭应用的 Windows 无障碍集成，从而规避崩溃（已有其他受影响产品验证此方案有效，详见上游 issue）。
  * 开启方式（二选一）：环境变量 `IRIS_DISABLE_WINDOWS_A11Y=1`，或命令行参数 `--disable-windows-a11y`（默认关闭）。
  * 代价：开启后屏幕阅读器无法读取本应用。该开关面向遇到此崩溃的机器；不受影响的机器保持完整无障碍支持。上游引擎修复（flutter/flutter#190903）发布后，本开关将被移除。
* 除上述兼容开关外，本版无其他变化。

## v2.0.0

### Changelog

* Fixed a Windows crash in the FVP playback backend: fvp 0.38.1 could crash while playing / tearing down videos and when closing the app; this build ships the patched FVP engine (upstream fixes #397 / #401, not yet released on pub)
* Fixed short video mode seek: swiping to fast-forward (or double-tapping) always started from the beginning of the video — seeks now start from the current playback position (all platforms)
* The 2.0 line brings the full dependency modernization: media stack (media_kit_video 2.0 / fvp / video_player 2.14), secure storage 11, file picker 13, permission handler 13, network drives (saf_util 3, win32 6), app links 7 — all dependencies are up to date
* The UI runs on Flutter's new standalone `material_ui` package (the Material library moved out of the Flutter SDK)
* Note: local playback history / settings reset once on the first launch after upgrading (secure storage format change)

### 更新日志

* 修复 Windows 端 FVP 播放后端的闪退：fvp 0.38.1 在播放/切换视频与关闭应用时可能崩溃；本版内置了已修复的 FVP 引擎（对应上游 #397 / #401，pub 尚未发版）
* 修复短视频模式快进：右滑快进（或双击快进）总是从视频开头开始 —— 现在从当前播放位置开始（全平台）
* 2.0 带来完整的依赖现代化：播放栈（media_kit_video 2.0 / fvp / video_player 2.14）、安全存储 11、文件选择 13、权限 13、网络盘（saf_util 3 / win32 6）、链接 7 等全部升级到最新
* 界面运行在 Flutter 新的独立 `material_ui` 包上（Material 库已从 SDK 拆出）
* 注意：升级后首次启动会重置一次本地播放历史 / 设置（安全存储格式变更）

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

# MediaMix Kotlin + Compose Multiplatform 重构方案

> 日期：2026-06-26
> 目标：将 MediaMix 从 Flutter/Dart 重构为 Kotlin + Compose Multiplatform
> 平台：Android + Desktop（Windows），本地运行，不部署服务器

---

## 一、技术选型明细

### 1.1 核心框架

| 技术 | 版本 | 选择理由 |
|------|------|----------|
| **Kotlin** | 2.1.x | 最新稳定版，支持 K2 编译器，Compose Compiler 已内置 |
| **Compose Multiplatform** | 1.7.x | JetBrains 官方跨平台 UI 框架，Android + Desktop 共用一套代码 |
| **Kotlin Multiplatform (KMP)** | 2.1.x | 共享业务逻辑层，平台特定实现通过 `expect/actual` 分离 |

### 1.2 视频播放

| 平台 | 技术 | 版本 | 选择理由 |
|------|------|------|----------|
| **Android** | **Media3 ExoPlayer** | 1.5.x | Google 官方推荐，Android 视频播放事实标准，硬解码/ABR/DASH/HLS 全支持 |
| **Desktop** | **mpv via Kotlin FFI** | mpv 0.38+ | 与现有 media_kit 底层一致（mpv），通过 `kotlin-native` FFI 或 JNA 桥接；备选方案：VLCJ (libvlc Java 绑定) |
| **抽象层** | 自定义 `PlayerEngine` 接口 | — | 统一 Android/Desktop 播放 API，上层业务代码不感知平台差异 |

### 1.3 网络层

| 技术 | 版本 | 选择理由 |
|------|------|------|
| **Ktor Client** | 3.0.x | Kotlin-first HTTP 客户端，跨平台（JVM + Native），协程原生支持，替代 Dio |
| **kotlinx-serialization** | 1.7.x | Kotlin 官方 JSON 序列化，编译时生成，性能优于 Gson/Moshi |
| **okhttp** | 4.12.x（仅 JVM） | Ktor JVM 引擎底层使用，也可直接用 OkHttp 替代 Ktor Client（Desktop 场景更灵活） |

### 1.4 数据库

| 技术 | 版本 | 选择理由 |
|------|------|------|
| **SQLDelight** | 2.0.x | Kotlin-first 数据库框架，编译时校验 SQL，支持多平台（JVM/Android/Native），与 Drift 理念相近 |
| **备选：Room** | 2.7.x | 仅 Android 支持，Desktop 需额外方案；若只做 Android 可选 Room |

> **决策**：选择 **SQLDelight**，因为它天然支持 KMP 跨平台，一套 `.sq` 文件同时生成 Android 和 Desktop 代码。

### 1.5 依赖注入

| 技术 | 版本 | 选择理由 |
|------|------|------|
| **Koin** | 4.0.x | Kotlin-first DI 框架，轻量级，无需注解处理器，KMP 兼容 |
| 备选：Hilt | — | 仅 Android，不支持 Desktop，排除 |

### 1.6 其他核心依赖

| 功能 | 库 | 版本 | 替代原项目中的 |
|------|-----|------|----------------|
| 协程 | kotlinx-coroutines | 1.9.x | Dart async/await |
| 响应式流 | kotlinx-flow | — | Riverpod StateNotifier |
| 路由/导航 | Navigation Compose | — | GoRouter |
| 图片加载 | Coil (Compose) | 3.0.x | cached_network_image |
| 轻量持久化 | multiplatform-settings | 1.2.x | shared_preferences |
| HTML 解析 | jsoup | 1.18.x | html 包（XPath 蜘蛛） |
| 日志 | kermit (TouchLab) | 2.0.x | logger |
| UUID | kotlinx-uuid 或 stately-uuid | — | uuid 包 |

### 1.7 项目构建

| 技术 | 版本 | 说明 |
|------|------|------|
| Gradle (Kotlin DSL) | 8.10+ | 项目构建系统 |
| KSP | 2.1.x-1.0.x | SQLDelight / Koin 代码生成 |

---

## 二、模块拆分规划

### 2.1 项目结构

```
mediamix-kmp/
├── shared/                          # 跨平台共享模块 (KMP commonMain)
│   ├── src/commonMain/kotlin/
│   │   ├── core/
│   │   │   ├── network/             # 网络层
│   │   │   │   ├── NetworkEngine.kt
│   │   │   │   ├── BandwidthEstimator.kt
│   │   │   │   ├── DnsResolver.kt
│   │   │   │   ├── RetryInterceptor.kt
│   │   │   │   └── CdnScheduler.kt
│   │   │   ├── database/            # 数据层
│   │   │   │   ├── sqldelight/      # .sq 文件
│   │   │   │   ├── DatabaseFactory.kt
│   │   │   │   └── daos/
│   │   │   ├── cache/               # 缓存系统
│   │   │   │   ├── VideoCacheService.kt
│   │   │   │   ├── MemoryCache.kt   # L1+L2
│   │   │   │   ├── DiskCache.kt     # L3+L4
│   │   │   │   ├── CacheStrategyManager.kt
│   │   │   │   └── LocalProxyServer.kt
│   │   │   └── services/            # 核心服务
│   │   │       ├── PreloadService.kt
│   │   │       ├── PowerManager.kt
│   │   │       ├── DeviceCapability.kt
│   │   │       ├── DownloadService.kt
│   │   │       └── PrivacyManager.kt
│   │   ├── spider/                  # 蜘蛛引擎
│   │   │   ├── SpiderAdapter.kt     # 接口
│   │   │   ├── SpiderRegistry.kt
│   │   │   ├── SpiderService.kt
│   │   │   ├── CmsSpider.kt
│   │   │   ├── JsonSpider.kt
│   │   │   ├── XpathSpider.kt
│   │   │   ├── JavaBridgeSpider.kt
│   │   │   ├── JavaBridgeManager.kt
│   │   │   ├── TvBoxConfigParser.kt
│   │   │   ├── TvBoxImageDecoder.kt
│   │   │   └── models/
│   │   ├── player/                  # 播放核心
│   │   │   ├── PlayerEngine.kt      # 抽象接口
│   │   │   ├── PlayerCoreManager.kt
│   │   │   ├── CacheEngine.kt
│   │   │   ├── PlaybackErrorHandler.kt
│   │   │   ├── MetricsEngine.kt
│   │   │   ├── AbrController.kt
│   │   │   ├── BufferManager.kt
│   │   │   └── SubtitleService.kt
│   │   ├── models/                  # 数据模型
│   │   │   ├── VideoModels.kt
│   │   │   ├── SpiderModels.kt
│   │   │   └── CacheModels.kt
│   │   └── di/                      # 依赖注入
│   │       └── SharedModule.kt
│   └── build.gradle.kts
│
├── androidApp/                      # Android 平台模块
│   ├── src/main/kotlin/
│   │   ├── platform/
│   │   │   ├── ExoPlayerEngine.kt   # ExoPlayer 实现
│   │   │   ├── AndroidDnsResolver.kt
│   │   │   ├── AndroidDatabaseFactory.kt
│   │   │   ├── AndroidPowerManager.kt
│   │   │   └── PipManager.kt
│   │   ├── ui/                      # Android 专属 UI（如有）
│   │   └── MainActivity.kt
│   └── build.gradle.kts
│
├── desktopApp/                      # Desktop (Windows) 平台模块
│   ├── src/main/kotlin/
│   │   ├── platform/
│   │   │   ├── MpvPlayerEngine.kt   # mpv FFI 实现
│   │   │   ├── DesktopDnsResolver.kt
│   │   │   ├── DesktopDatabaseFactory.kt
│   │   │   └── DesktopPowerManager.kt
│   │   ├── ui/                      # Desktop 专属 UI（如有）
│   │   └── Main.kt
│   └── build.gradle.kts
│
├── composeUi/                       # 跨平台 Compose UI 模块
│   ├── src/commonMain/kotlin/
│   │   ├── theme/                   # Material 3 主题
│   │   ├── components/              # 共享 UI 组件
│   │   ├── screens/
│   │   │   ├── VideoHomeScreen.kt
│   │   │   ├── VideoDetailScreen.kt
│   │   │   ├── PlayerScreen.kt
│   │   │   ├── SearchScreen.kt
│   │   │   ├── HistoryScreen.kt
│   │   │   ├── FavoriteScreen.kt
│   │   │   ├── SettingsScreen.kt
│   │   │   ├── SourceManageScreen.kt
│   │   │   └── DownloadScreen.kt
│   │   ├── navigation/
│   │   │   └── AppNavigation.kt
│   │   └── viewmodel/
│   │       ├── VideoHomeViewModel.kt
│   │       ├── PlayerViewModel.kt
│   │       └── ...
│   └── build.gradle.kts
│
└── build.gradle.kts                 # 根构建文件
```

### 2.2 Dart → Kotlin 模块映射关系

| 原 Dart 模块 | 行数 | → Kotlin 模块 | 迁移难度 | 说明 |
|-------------|------|--------------|----------|------|
| `core/database/database.dart` | 324 | `shared/core/database/` (SQLDelight .sq) | 中 | Schema 直接翻译，DAO 方法翻译 SQL |
| `core/network/network_engine.dart` | 1,236 | `shared/core/network/` | 中 | Dio→Ktor，逻辑 1:1 迁移，拆分为 5-6 个文件 |
| `core/services/video_cache_service.dart` | 1,792 | `shared/core/cache/` | 高 | 最大单文件，**建议拆分为 4 个文件**再迁移 |
| `core/services/local_proxy_server.dart` | 415 | `shared/core/cache/LocalProxyServer.kt` | 中 | HTTP 代理逻辑，Ktor Server 或 raw socket |
| `core/services/preload_service.dart` | 760 | `shared/core/services/PreloadService.kt` | 低 | 纯逻辑，直接翻译 |
| `core/services/cache_strategy_manager.dart` | 582 | `shared/core/cache/CacheStrategyManager.kt` | 低 | 纯逻辑，直接翻译 |
| `core/services/power_manager_service.dart` | 364 | `shared/` 接口 + `androidApp/` `desktopApp/` actual | 中 | 平台相关，需 expect/actual |
| `core/services/device_capability_service.dart` | 366 | `shared/` 接口 + platform actual | 中 | 硬解码探测平台相关 |
| `core/services/player_metrics_service.dart` | 723 | `shared/core/services/` | 低 | 纯逻辑 |
| `core/services/data_reporter_service.dart` | 450 | `shared/core/services/` | 低 | 纯逻辑 |
| `features/video/services/spider/*` (11 文件) | 2,135 | `shared/spider/` | 低 | 已良好抽象，接口直接映射 |
| `features/video/core/engines/*` (4 文件) | 750 | `shared/player/` | 低 | 已有接口定义 |
| `features/video/core/player_core_manager.dart` | 955 | `shared/player/PlayerCoreManager.kt` | 高 | 需重新设计播放器抽象层 |
| `features/video/core/player_core.dart` | 356 | `shared/player/` (BufferManager + ABR) | 中 | 拆分到 BufferManager.kt + AbrController.kt |
| `features/video/models/video_models.dart` | 489 | `shared/models/` | 低 | data class 直接翻译 |
| `features/video/services/tbox_api_service.dart` | 801 | `shared/spider/TboxApiService.kt` | 低 | 纯网络请求逻辑 |
| `features/video/services/subtitle_service.dart` | 416 | `shared/player/SubtitleService.kt` | 低 | 纯逻辑 |
| `features/video/providers/video_providers.dart` | 652 | `composeUi/viewmodel/` | 中 | Riverpod → ViewModel + Flow |
| `features/video/pages/*` (6 文件) | 3,030 | `composeUi/screens/` | 中 | Flutter Widget → Compose，需重新设计布局 |
| `features/settings/pages/*` (3 文件) | 883 | `composeUi/screens/` | 低 | 简单设置页面 |
| `app/router.dart` | 112 | `composeUi/navigation/` | 低 | GoRouter → Navigation Compose |

### 2.3 大文件拆分方案

重构时同步拆分超大文件：

| 原文件 | 行数 | 拆分为 |
|--------|------|--------|
| `video_cache_service.dart` | 1,792 | `MemoryCache.kt` (L1+L2, ~300行) + `DiskCache.kt` (L3+L4, ~400行) + `VideoCacheService.kt` (协调层, ~300行) + `CacheIndex.kt` (索引管理, ~200行) |
| `network_engine.dart` | 1,236 | `NetworkEngine.kt` (~200行) + `BandwidthEstimator.kt` (~250行) + `DnsResolver.kt` (~200行) + `Interceptors.kt` (~300行) + `CdnScheduler.kt` (~150行) |
| `player_page.dart` | 1,368 | `PlayerScreen.kt` (~400行) + `PlayerControls.kt` (~300行) + `PlayerOverlay.kt` (~200行) + `GestureHandler.kt` (~200行) |
| `player_core_manager.dart` | 955 | `PlayerCoreManager.kt` (~300行) + `PlaybackController.kt` (~250行) + `QualityManager.kt` (~200行) |

---

## 三、平台适配策略

### 3.1 视频播放方案

#### Android — Media3 ExoPlayer

```kotlin
// shared/player/PlayerEngine.kt (expect)
expect class PlayerEngine() {
    fun initialize()
    fun setSource(url: String)
    fun play()
    fun pause()
    fun seekTo(positionMs: Long)
    fun setPlaybackSpeed(speed: Float)
    fun setVolume(volume: Float)
    fun release()
    // ...
}

// androidApp/platform/ExoPlayerEngine.kt (actual)
actual class PlayerEngine {
    private var exoPlayer: ExoPlayer? = null
    actual fun initialize() {
        exoPlayer = ExoPlayer.Builder(context).build()
    }
    // ExoPlayer 原生 API 调用
}
```

**ExoPlayer 优势**：
- 硬解码/软解码自动切换
- 原生 HLS/DASH 支持
- ABR 内置
- PiP 原生支持
- 与 Android 系统深度集成（音频焦点、媒体会话）

#### Desktop — mpv via JNA/JNI

```kotlin
// desktopApp/platform/MpvPlayerEngine.kt (actual)
actual class PlayerEngine {
    private val mpvHandle: Long  // mpv C API handle via JNA

    actual fun initialize() {
        mpvHandle = MpvLib.mpv_create()
        MpvLib.mpv_initialize(mpvHandle)
    }
    actual fun setSource(url: String) {
        MpvLib.mpv_command(mpvHandle, arrayOf("loadfile", url))
    }
    // ...
}
```

**mpv 方案选择理由**：
- 与现有 media_kit 底层一致（都是 mpv），行为可预期
- 跨平台（Windows/Linux/macOS），未来扩展无阻力
- 通过 JNA 直接调用 mpv C API，性能损耗极小
- 备选：VLCJ（libvlc），但体积更大、API 更复杂

**Desktop mpv 分发方式**：
- 将 mpv-1.dll + 依赖 DLL 打包到应用 resources 中
- 启动时解压到临时目录，JNA 加载

### 3.2 文件存储与缓存路径

| 路径类型 | Android | Desktop (Windows) |
|----------|---------|-------------------|
| 应用数据 | `context.filesDir` | `System.getProperty("user.home")/.mediamix/` |
| 缓存目录 | `context.cacheDir` | `System.getProperty("user.home")/.mediamix/cache/` |
| 数据库 | `context.filesDir/mediamix.db` | `~/.mediamix/mediamix.db` |
| 下载目录 | `Environment.DIRECTORY_DOWNLOADS/MediaMix` | `user.home/Downloads/MediaMix/` |
| 临时文件 | `context.cacheDir/tmp/` | `System.getProperty("java.io.tmpdir")/mediamix/` |

通过 `expect/actual` 封装：

```kotlin
// shared/core/PlatformPaths.kt
expect object PlatformPaths {
    val dataDir: String
    val cacheDir: String
    val downloadDir: String
    val tempDir: String
}
```

### 3.3 Java Bridge 运行方式

**重构后的重大改进**：Kotlin 运行在 JVM 上，可以直接加载 Java JAR，**不再需要 HTTP 桥接**。

| 方案 | 实现方式 | 优劣 |
|------|----------|------|
| **方案 A：JVM 内直接加载（推荐）** | 通过 `URLClassLoader` 加载 TVBox 蜘蛛 JAR，反射调用方法 | 零网络开销，最低延迟，无需启动额外进程 |
| 方案 B：保留 HTTP 桥接 | 继续使用 SpiderBridgeServer.java 独立进程 | 兼容现有方案，但有进程管理开销 |

**方案 A 实现思路**：

```kotlin
class JavaBridgeManager {
    private var classLoader: URLClassLoader? = null

    fun loadSpiderJar(jarPath: String) {
        val jarFile = File(jarPath)
        classLoader = URLClassLoader(arrayOf(jarFile.toURI().toURL()), javaClass.classLoader)
    }

    fun invokeSpiderMethod(className: String, method: String, args: Array<Any?>): Any? {
        val clazz = classLoader!!.loadClass(className)
        val instance = clazz.getDeclaredConstructor().newInstance()
        return clazz.getMethod(method, *args.map { it?.javaClass }.toTypedArray()).invoke(instance, *args)
    }
}
```

**优势**：
- 消除 HTTP 序列化/反序列化开销
- 无需管理 Java 子进程生命周期
- 无需端口冲突处理
- 错误堆栈直接可见，调试更方便

**注意**：TVBox 蜘蛛 JAR 中的 `csp_*Guard` 类可能依赖 Android API（如 `Context`），需要在 `JavaBridgeManager` 中提供 Mock/Stub 对象。

### 3.4 平台特定功能

| 功能 | Android 实现 | Desktop 实现 |
|------|-------------|-------------|
| PiP 画中画 | `Activity.enterPictureInPictureMode()` | 不支持（或独立小窗口） |
| 电池/功耗 | `BatteryManager` API | 读取系统电源状态（Win32 API via JNA） |
| 硬解码探测 | `MediaCodecList` | mpv 内置硬解码支持（DXVA2/D3D11VA on Windows） |
| 网络状态 | `ConnectivityManager` | JNA 调用 `NetworkListManager` |
| 后台播放 | `ForegroundService` | 系统托盘 + 独立线程 |
| 屏幕亮度 | `WindowManager.LayoutParams` | 暂不支持 |

---

## 四、迁移优先级和阶段划分

### 阶段 1：基础设施（1-2 周）

**目标**：搭建 KMP 项目骨架，数据层和网络层就绪

| 任务 | 内容 | 产出 |
|------|------|------|
| 1.1 | 创建 KMP Gradle 项目结构（shared + androidApp + desktopApp + composeUi） | 可编译的空项目 |
| 1.2 | 配置依赖（Ktor、SQLDelight、Koin、kotlinx-serialization） | build.gradle.kts |
| 1.3 | 迁移数据库 Schema（Drift → SQLDelight） | 7 张表的 .sq 文件 + DAO |
| 1.4 | 迁移数据模型（video_models.dart → Kotlin data class） | models/ |
| 1.5 | 迁移网络引擎核心（NetworkEngine + BandwidthEstimator） | network/ |
| 1.6 | 配置 Koin DI 模块 | di/SharedModule.kt |

**验证**：单元测试通过，数据库 CRUD 正常，网络请求正常

### 阶段 2：蜘蛛引擎 + 缓存系统（2-3 周）

**目标**：数据获取和缓存能力就绪

| 任务 | 内容 | 产出 |
|------|------|------|
| 2.1 | 迁移 SpiderAdapter 接口 + 4 种蜘蛛实现 | spider/ |
| 2.2 | 迁移 SpiderRegistry + SpiderService | spider/ |
| 2.3 | 迁移 TvBoxConfigParser + TvBoxImageDecoder | spider/ |
| 2.4 | 实现 JavaBridgeManager（JVM 内直接加载方案） | spider/ |
| 2.5 | 迁移缓存系统（拆分后迁移） | cache/ |
| 2.6 | 迁移 LocalProxyServer | cache/ |
| 2.7 | 迁移 CacheStrategyManager | cache/ |
| 2.8 | 迁移 PreloadService | services/ |

**验证**：能获取饭太硬等 TVBox 源的视频数据，缓存写入/读取正常

### 阶段 3：播放核心（2-3 周）

**目标**：视频播放全链路打通

| 任务 | 内容 | 产出 |
|------|------|------|
| 3.1 | 定义 PlayerEngine 抽象接口 | player/PlayerEngine.kt |
| 3.2 | 实现 ExoPlayerEngine（Android actual） | androidApp/ |
| 3.3 | 实现 MpvPlayerEngine（Desktop actual） | desktopApp/ |
| 3.4 | 迁移 PlayerCoreManager | player/ |
| 3.5 | 迁移三个引擎（CacheEngine + ErrorHandler + MetricsEngine） | player/ |
| 3.6 | 迁移 ABR 控制器 + BufferManager | player/ |
| 3.7 | 迁移 SubtitleService | player/ |
| 3.8 | 迁移功耗管理（expect/actual） | services/ + platform/ |

**验证**：Android 和 Desktop 均可播放视频，换源/字幕/进度记忆正常

### 阶段 4：UI 层（2-3 周）

**目标**：全部页面用 Compose Multiplatform 重写

| 任务 | 内容 | 产出 |
|------|------|------|
| 4.1 | 搭建 Material 3 主题 + 导航框架 | composeUi/theme/ + navigation/ |
| 4.2 | 迁移视频首页 + 详情页 | screens/ |
| 4.3 | 迁移播放器页面（最复杂） | screens/PlayerScreen.kt |
| 4.4 | 迁移搜索/历史/收藏页 | screens/ |
| 4.5 | 迁移设置/源管理/下载页 | screens/ |
| 4.6 | 迁移所有 ViewModel（Riverpod → ViewModel） | viewmodel/ |

**验证**：全部功能可操作，UI 在 Android 和 Desktop 上正常显示

### 阶段 5：收尾与优化（1-2 周）

| 任务 | 内容 |
|------|------|
| 5.1 | 补充单元测试（目标：核心模块覆盖率 ≥ 60%） |
| 5.2 | Compose UI 测试（关键页面） |
| 5.3 | 性能调优（启动速度、内存占用） |
| 5.4 | 打包发布（Android APK + Windows MSI/EXE） |
| 5.5 | 更新文档 |

### 总工期估算

| 阶段 | 时间 | 累计 |
|------|------|------|
| 阶段 1：基础设施 | 1-2 周 | 1-2 周 |
| 阶段 2：蜘蛛 + 缓存 | 2-3 周 | 3-5 周 |
| 阶段 3：播放核心 | 2-3 周 | 5-8 周 |
| 阶段 4：UI 层 | 2-3 周 | 7-11 周 |
| 阶段 5：收尾 | 1-2 周 | **8-13 周** |

---

## 五、风险评估

### 5.1 高风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **Desktop mpv 集成复杂度** | JNA 绑定 mpv C API 需要处理内存管理、回调、线程安全，调试困难 | 先用 VLCJ 做原型验证；或 Desktop 端暂用 WebView + HLS.js 作为过渡方案 |
| **TVBox 蜘蛛 JAR 的 Android 依赖** | `csp_*Guard` 类可能引用 `android.content.Context` 等 API，在 Desktop JVM 上无法运行 | 提供 Mock Context 实现；若依赖过深则退回 HTTP 桥接方案 |
| **Compose Multiplatform Desktop 成熟度** | Desktop 端部分 Compose 组件行为与 Android 不一致（字体渲染、窗口管理、文件对话框） | 平台差异部分用 `expect/actual` 隔离；关注 JetBrains 官方更新 |

### 5.2 中风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **LocalProxyServer 迁移** | 需要跨平台 HTTP 代理服务器，Dart `HttpServer` → Kotlin 没有直接等价物 | 使用 Ktor Server（嵌入式）或 Java `com.sun.net.httpserver.HttpServer` |
| **边播边缓存代理的 Range 请求处理** | 需要精确控制 HTTP Range 响应，与播放器行为强耦合 | 迁移时保持现有逻辑不变，仅翻译语言 |
| **数据库迁移（Drift → SQLDelight）** | SQL 语法差异、事务行为差异、迁移脚本不兼容 | 首次安装时重新建表（个人项目无需数据迁移） |
| **ExoPlayer 与 mpv 行为差异** | 同一视频在两个平台上的缓冲策略、错误处理可能不一致 | PlayerEngine 接口设计足够抽象，允许平台差异；业务层做兼容处理 |

### 5.3 低风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **Ktor vs OkHttp 性能差异** | Ktor 在 JVM 上底层就是 OkHttp，性能无差异 | 无风险 |
| **SQLDelight 学习成本** | 语法与 Drift 略有不同 | SQL 基础相同，学习曲线平缓 |
| **测试框架切换** | Dart test → Kotlin test (JUnit + Turbine + MockK) | 测试逻辑可直接翻译，框架差异不大 |
| **项目体积增大** | KMP 项目 Gradle 配置较复杂 | 使用版本目录（Version Catalog）管理依赖 |

### 5.4 已知限制

| 限制 | 说明 |
|------|------|
| **PiP 仅 Android 支持** | Desktop 无原生 PiP，需自行实现小窗口或放弃 |
| **硬解码平台差异** | Android 用 MediaCodec，Desktop 用 mpv 内置（DXVA2），行为不完全一致 |
| **Compose Desktop 无原生系统托盘** | 需要 AWT `SystemTray` 补充 |

---

## 六、与现有 Flutter 项目的对比

| 维度 | Flutter/Dart（现状） | Kotlin/Compose（重构后） |
|------|---------------------|-------------------------|
| 代码量 | ~19K 行 Dart | 预估 ~15K 行 Kotlin（更简洁） |
| 视频播放 | media_kit (mpv 封装) | ExoPlayer (Android) + mpv (Desktop) |
| 蜘蛛引擎 | Dart + HTTP Bridge (Java) | **JVM 直接加载 JAR（消除 Bridge）** |
| 数据库 | Drift (代码生成 4400 行) | SQLDelight (编译时校验，生成代码更少) |
| 状态管理 | Riverpod | ViewModel + Flow |
| 网络 | Dio | Ktor Client |
| 测试框架 | flutter_test | JUnit + MockK + Turbine |
| 构建系统 | Flutter CLI | Gradle |
| APK 体积 | ~102MB (media_kit native libs) | Android ~30MB (ExoPlayer 精简)；Desktop ~50MB (含 mpv DLL) |

---

## 七、决策记录

| 决策项 | 选择 | 否决方案 | 理由 |
|--------|------|----------|------|
| 数据库 | SQLDelight | Room | Room 不支持 Desktop |
| 网络 | Ktor Client | Retrofit | Retrofit 不支持 KMP |
| DI | Koin | Hilt/Dagger | Hilt 仅 Android；Dagger 过重 |
| Desktop 播放 | mpv via JNA | VLCJ | mpv 与现有底层一致，体积更小 |
| Java Bridge | JVM 内直接加载 | HTTP 桥接 | 消除进程间通信开销 |
| UI 框架 | Compose Multiplatform | JavaFX/Swing | Compose 与 Android 共用 UI 代码 |

---

## 阶段六「功能完善与发布准备」

> 前置条件：阶段一~五已完成，累计 ~18,840 行 Kotlin 代码，613 个测试。
> 当前存在 4 个关键阻塞项和多个 TODO 占位需完善，本阶段目标是全部清零并达到发布状态。

### 6.1 关键阻塞项（P0）

| # | 阻塞项 | 现状 | 修复方案 | 预估工时 |
|---|--------|------|----------|----------|
| P0-1 | **ProGuard 规则缺失** | `LocalProxyServer` 使用 `com.sun.net.httpserver.*`，R8 混淆后崩溃 | `proguard-rules.pro` 添加 dontwarn/keep 规则 | 15 分钟 |
| P0-2 | **DatabaseDriverFactory 缺失** | SQLDelight 7 个 `.sq` 文件已定义，但无 expect/actual Driver 创建代码，`SharedModule` 未注册数据库 | 新增 expect/actual `DatabaseDriverFactory` + Repository 层 + `SharedModule` 注册 | 2 小时 |
| P0-3 | **视频渲染 Surface 缺失** | `PlayerScreen.kt` 视频区域为黑色 `Box` 占位，`composeUi` 无 `androidMain`/`desktopMain` 源集 | 新增平台源集 + expect/actual `VideoSurface`（Android: `AndroidView`+`PlayerView`；Desktop: JNA 嵌入 mpv 窗口） | 4 小时 |
| P0-4 | **Android Koin 初始化待确认** | `MediaMixApp.kt` 中 `startKoin` 调用需验证完整性（模块注册、平台 actual 注入） | 逐一核对 `SharedModule` 注册项，补充平台特定模块 | 30 分钟 |

### 6.2 功能完善（P1）

| # | 功能项 | 现状 | 完善方案 |
|---|--------|------|----------|
| P1-1 | **ViewModel 接入真实数据库** | `HistoryViewModel` / `FavoriteViewModel` 当前使用 TODO 占位 | 接入 SQLDelight DAO，实现真实 CRUD + Flow 观察 |
| P1-2 | **SettingsViewModel 功能补全** | `exportData` / `clearCache` / `cacheStats` 均为 TODO | 实现数据导出（JSON）、缓存清理（递归删除）、缓存统计（目录遍历） |
| P1-3 | **DownloadScreen 接入真实逻辑** | 当前完全占位，无实际功能 | 接入 `DownloadService`，实现下载列表、进度展示、暂停/恢复 |
| P1-4 | **字幕叠加层** | `PlayerScreen` 字幕文本为 `null` 占位 | 接入 `SubtitleService`，实现字幕渲染叠加层（SRT/ASS 解析 + Compose Text 叠加） |

### 6.3 工程化（P2）

| # | 工程化项 | 内容 |
|---|----------|------|
| P2-1 | **CI/CD 流水线** | GitHub Actions：自动构建 + 测试 + 打包（Android APK + Desktop 安装包） |
| P2-2 | **代码质量工具** | detekt（静态分析）+ ktlint（代码格式化）配置，集成到 Gradle 和 CI |
| P2-3 | **Release 签名** | Android keystore 配置、签名 Gradle task、密钥安全管理 |

### 6.4 任务拆分（8 个任务，4 波次）

#### Wave 1（并行，无依赖）

| 任务 | 内容 | 预估工时 |
|------|------|----------|
| **Task A** | ProGuard 规则修复 + Android Koin 初始化验证 | ~30 分钟 |
| **Task B** | `DatabaseDriverFactory` expect/actual + Repository 层 + `SharedModule` 注册 | ~2 小时 |

**Task A 详细步骤**：
1. `androidApp/proguard-rules.pro` 添加：
   ```proguard
   -dontwarn com.sun.net.httpserver.**
   -keep class com.sun.net.httpserver.** { *; }
   -keep class io.ktor.server.sun.** { *; }
   ```
2. 验证 `MediaMixApp.kt` 中 `startKoin { modules(...) }` 包含所有必需模块
3. 执行 `./gradlew :androidApp:assembleRelease` 验证 R8 不崩溃

**Task B 详细步骤**：
1. `shared/src/commonMain` 新增 `expect fun createDatabaseDriver(): SqlDriver`
2. `androidApp/src/main` 新增 `actual fun`（Android SQLite）
3. `desktopApp/src/main` 新增 `actual fun`（JDBC SQLite）
4. 为 7 张表创建 Repository 类（`HistoryRepository`、`FavoriteRepository` 等）
5. 在 `SharedModule` 中注册 Database + 所有 Repository

#### Wave 2（并行，等 Wave 1 完成）

| 任务 | 内容 | 预估工时 |
|------|------|----------|
| **Task C** | 视频渲染 Surface expect/actual + `composeUi` 平台源集 | ~4 小时 |
| **Task D** | ViewModel 接入 SQLDelight DAO（History / Favorite / Settings / Download） | ~2 小时 |

**Task C 详细步骤**：
1. `composeUi/build.gradle.kts` 新增 `androidMain` / `desktopMain` 源集配置
2. `composeUi/src/commonMain` 新增 `expect fun VideoSurface(modifier, playerEngine)`
3. `composeUi/src/androidMain` 实现 `AndroidView` + `PlayerView`（ExoPlayer 渲染）
4. `composeUi/src/desktopMain` 实现 JNA mpv 窗口嵌入（Swing `JPanel` + `AndroidView` 桥接）
5. `PlayerScreen.kt` 中黑色 `Box` 替换为 `VideoSurface`

**Task D 详细步骤**：
1. `HistoryViewModel` — 注入 `HistoryRepository`，替换 TODO 为真实查询
2. `FavoriteViewModel` — 注入 `FavoriteRepository`，替换 TODO 为真实 CRUD
3. `SettingsViewModel` — 实现 `exportData`（JSON 序列化导出）、`clearCache`（递归删除缓存目录）、`cacheStats`（目录大小计算）
4. `DownloadViewModel` — 注入 `DownloadService`，实现下载管理

#### Wave 3（等 Wave 2 完成）

| 任务 | 内容 | 预估工时 |
|------|------|----------|
| **Task E** | 字幕叠加层 + `PlayerScreen` 完善 | ~2 小时 |
| **Task F** | `DownloadScreen` 接入真实逻辑 | ~1.5 小时 |

**Task E 详细步骤**：
1. 实现 SRT/ASS 字幕解析（复用 `SubtitleService`）
2. `PlayerScreen` 添加字幕 `Text` 叠加层，绑定播放器时间轴
3. 字幕开关、字号调节 UI

**Task F 详细步骤**：
1. `DownloadScreen` 接入 `DownloadViewModel`（Task D 已完成）
2. 实现下载列表 UI（进度条、状态指示）
3. 实现暂停/恢复/删除操作

#### Wave 4（等全部完成）

| 任务 | 内容 | 预估工时 |
|------|------|----------|
| **Task G** | CI/CD + 代码质量工具 + Release 签名 | ~3 小时 |
| **Task H** | 全量构建验证 + 测试 | ~1 小时 |

**Task G 详细步骤**：
1. 创建 `.github/workflows/build.yml`：checkout → setup JDK → `./gradlew build` → `./gradlew test` → 打包
2. 配置 detekt + ktlint Gradle 插件，CI 中执行 `./gradlew detekt ktlintCheck`
3. 配置 Android 签名：`keystore.properties` + `signingConfigs` + `buildTypes.release`

**Task H 详细步骤**：
1. `./gradlew build` 全量编译（含 R8 Release）
2. `./gradlew test` 全量测试
3. `./gradlew :androidApp:assembleRelease` APK 构建
4. `./gradlew :desktopApp:packageDistributionForCurrentOS` Desktop 包构建
5. 手动验证：视频播放、历史/收藏读写、字幕显示

### 6.5 依赖图

```
Task A (ProGuard+Koin) ──────────────────────────────┐
Task B (DatabaseDriverFactory+Repository) ─→ Task D ─┤
                                                      ├→ Task H (全量验证)
Task C (VideoSurface) ─→ Task E (字幕+PlayerScreen) ─┤
Task D (ViewModel+DAO) ─→ Task F (DownloadScreen) ───┤
Task G (CI/CD+工具) ─────────────────────────────────┘
```

### 6.6 验证标准

| # | 验证项 | 通过条件 |
|---|--------|----------|
| 1 | `./gradlew build` | 全量编译通过（含 R8 Release 构建，零 warning 阻塞） |
| 2 | `./gradlew :androidApp:assembleRelease` | APK 构建成功，可安装运行 |
| 3 | `./gradlew :desktopApp:packageDistributionForCurrentOS` | Desktop 安装包可用 |
| 4 | `./gradlew test` | 所有测试通过（预期 650+） |
| 5 | 视频播放器 | Android + Desktop 均可实际渲染画面（非黑屏） |
| 6 | 历史/收藏 | 可真实读写 SQLDelight 数据库，重启后数据持久 |

### 6.7 工时估算

| 波次 | 任务 | 工时 |
|------|------|------|
| Wave 1 | Task A + Task B | ~2.5 小时 |
| Wave 2 | Task C + Task D | ~6 小时 |
| Wave 3 | Task E + Task F | ~3.5 小时 |
| Wave 4 | Task G + Task H | ~4 小时 |
| **合计** | | **~16 小时（约 2 个工作日）** |

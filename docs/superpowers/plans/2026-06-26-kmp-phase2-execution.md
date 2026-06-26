# 阶段二「蜘蛛引擎 + 缓存系统」执行计划

## Context

KMP 重构阶段一已完成基础框架搭建（4 模块、expect/actual、数据模型、SQLDelight）。阶段二需要迁移蜘蛛引擎（12 个 Dart 文件 ~2,500 行）和缓存系统（4 个 Dart 文件 ~3,550 行），共 ~6,050 行 Dart 代码翻译为 Kotlin。

**关键发现**：阶段一创建的 `SpiderModels.kt` 中 `TvBoxSite` 与 Dart 源码有差异（type 是 String 而非 Int，缺少 isJavaSpider 等字段），需要先修正。此外，网络层（Ktor HttpClient 工厂）尚未建立，是蜘蛛引擎的前置依赖。

**用户决策**：
- LocalProxyServer → 使用 `com.sun.net.httpserver`（JVM 内置）
- TvBoxSite 模型 → 立即修正对齐 Dart 源码
- VideoApiService → 纳入任务 2.1 与蜘蛛一起迁移

---

## 任务分解与依赖关系

```
Task 1 (模型修正+网络基础) ─┬─→ Task 2 (蜘蛛引擎) ──→ Task 5 (Registry+Service)
                             ├─→ Task 3 (JavaBridge)  ──→ Task 5
                             ├─→ Task 4 (ConfigParser+ImageDecoder) ──→ Task 5
                             │
Task 6 (CacheStrategy) ─────┤
                             │
Task 7 (缓存系统) ──────────┼─→ Task 8 (LocalProxy) ──┐
                             ├─→ Task 9 (Preload)     ─├─→ Task 10 (集成验证)
                             └─────────────────────────┘
```

---

## Task 1: 模型修正 + 网络基础设施（前置任务）

**目标**：修正 TvBoxSite/TvBoxConfig 模型对齐 Dart 源码，创建共享 Ktor HttpClient 工厂

**文件清单**：
- 修改 `shared/src/commonMain/kotlin/com/mediamix/shared/models/SpiderModels.kt`
  - TvBoxSite: `type: String` → `type: Int`，`apiUrl` → `api`，添加 `jar/playerType/searchable/quickSearch/changeable`，添加 `isJavaSpider` 计算属性
  - TvBoxConfig: 添加 `spiderUrl` 字段
  - TvBoxLive: 添加 `type/playerType` 字段
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/network/HttpClientFactory.kt`
  - 提供 `createHttpClient()` 方法，配置超时、UA、日志拦截器
  - 各蜘蛛和缓存服务通过 Koin 注入或直接调用

**验证**：`./gradlew :shared:compileKotlinDesktop` 通过

---

## Task 2: 蜘蛛引擎 — 4 种蜘蛛 + VideoApiService（任务 2.1）

**依赖**：Task 1 完成

**目标**：迁移 SpiderAdapter 接口、CmsSpider、JsonSpider、XpathSpider、JavaBridgeSpider（骨架）+ VideoApiService

**文件清单**：
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/SpiderAdapter.kt`（接口）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/CmsSpider.kt`（~120行）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/JsonSpider.kt`（~260行）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/XpathSpider.kt`（~360行，html→jsoup）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/JavaBridgeSpider.kt`（骨架，等 Task 3 完成 JavaBridgeManager）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/VideoApiService.kt`（~800行，拆分为 VideoApiService + DnsCache + PrefetchCache）
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/spider/JsonSpiderTest.kt`
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/spider/XpathSpiderTest.kt`

**关键迁移映射**：
- `Dio` → `Ktor HttpClient`
- `html` 包 → `jsoup`（querySelectorAll → select, querySelector → selectFirst）
- `dart:convert jsonDecode` → `kotlinx.serialization` 或 `Json.parseToJsonElement`

**验证**：编译通过 + 单元测试通过

---

## Task 3: JavaBridgeManager — JVM 内直接加载 JAR（任务 2.4）

**依赖**：Task 1 完成（需要 SpiderAdapter 接口）

**目标**：实现 JVM 内 URLClassLoader 直接加载 TVBox 蜘蛛 JAR，替代原 HTTP Bridge 进程间通信

**文件清单**：
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/JavaBridgeManager.kt`（expect/actual 或纯 commonMain JVM 代码）
- 新建 `shared/src/desktopMain/kotlin/com/mediamix/shared/spider/DesktopJavaBridgeManager.kt`（actual: URLClassLoader 实现）
- 新建 `shared/src/androidMain/kotlin/com/mediamix/shared/spider/AndroidJavaBridgeManager.kt`（actual: DexClassLoader 或 URLClassLoader）
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/spider/JavaBridgeManagerTest.kt`

**核心设计**：
```kotlin
// commonMain - expect
expect class JavaBridgeManager() {
    fun loadSpiderJar(jarPath: String)
    fun invokeMethod(className: String, method: String, args: Array<Any?>): Any?
    fun release()
}
```

**注意**：TVBox 蜘蛛 JAR 中的 `csp_*Guard` 类可能依赖 Android API，需要提供 Mock/Stub

**验证**：编译通过 + 单元测试（Mock JAR 加载）

---

## Task 4: TvBoxConfigParser + TvBoxImageDecoder（任务 2.3）

**依赖**：Task 1 完成（需要修正后的 TvBoxConfig/TvBoxSite 模型）

**目标**：迁移 TVBox 配置解析器和图片伪装解码器

**文件清单**：
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/TvBoxConfigParser.kt`（~180行）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/TvBoxImageDecoder.kt`（~330行）
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/spider/TvBoxConfigParserTest.kt`
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/spider/TvBoxImageDecoderTest.kt`

**关键迁移点**：
- GBK 解码 → JVM 内置 `String(bytes, charset("GBK"))`
- Base64 → `java.util.Base64` 或 `kotlinx.coroutines` 中的工具
- 二进制操作 → `ByteArray` 替代 `List<int>` / `Uint8List`

**验证**：编译通过 + 单元测试（含饭太硬图片伪装格式测试用例）

---

## Task 5: SpiderRegistry + SpiderService（任务 2.2）

**依赖**：Task 2、3、4 全部完成

**目标**：迁移蜘蛛注册表和服务统一入口

**文件清单**：
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/SpiderRegistry.kt`（~140行）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/spider/SpiderService.kt`（~190行）
- 更新 `shared/src/commonMain/kotlin/com/mediamix/shared/di/SharedModule.kt`（注册蜘蛛相关 Koin 模块）
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/spider/SpiderRegistryTest.kt`

**验证**：编译通过 + 单元测试

---

## Task 6: CacheStrategyManager（任务 2.7）

**依赖**：Task 1 完成（需要 multiplatform-settings）

**目标**：迁移观看习惯追踪和动态缓存策略引擎

**文件清单**：
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/cache/CacheStrategyManager.kt`（~580行，从 cache_strategy_manager.dart 翻译）
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/cache/CacheStrategyManagerTest.kt`

**关键迁移点**：
- `SharedPreferences` → `multiplatform-settings`（`Settings` 接口）
- `dart:convert jsonEncode/jsonDecode` → `kotlinx.serialization`
- `Timer.periodic` → `CoroutineScope` + `launch`
- 纯逻辑部分（时段分析、类型偏好、TTL 计算）直接翻译

**验证**：编译通过 + 单元测试

---

## Task 7: 缓存系统核心（任务 2.5）

**依赖**：Task 1 完成 + Task 6 完成（CacheStrategyManager 集成）

**目标**：将 video_cache_service.dart（1792行）拆分为 4 个 Kotlin 模块并迁移

**文件清单**：
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/cache/CacheModels.kt`（~150行，CachePolicy/CacheEntry/SegmentCacheResult/CacheStats/MemoryPressureLevel/MemoryUsageInfo）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/cache/MemoryCache.kt`（~250行，L1 帧缓存 + L2 分段缓存）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/cache/DiskCache.kt`（~400行，L3 视频缓存 + L4 分段缓存 + CacheIndex）
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/cache/VideoCacheService.kt`（~500行，编排层：初始化/淘汰/统计/策略）
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/cache/MemoryCacheTest.kt`
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/cache/DiskCacheTest.kt`
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/cache/VideoCacheServiceTest.kt`

**关键迁移点**：
- `path_provider` → `PlatformPaths`（阶段一已有 expect/actual）
- `dart:io File/Directory` → `okio` 或 `java.io.File`（JVM 通用）
- 4 阶段淘汰算法直接翻译
- 内存压力检测 → expect/actual（或注入 `MemoryReader` 函数）

**验证**：编译通过 + 单元测试

---

## Task 8: LocalProxyServer（任务 2.6）

**依赖**：Task 7 完成（需要 VideoCacheService）

**目标**：迁移本地 HTTP 代理服务器，使用 `com.sun.net.httpserver.HttpServer`

**文件清单**：
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/cache/LocalProxyServer.kt`（~415行）
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/cache/LocalProxyServerTest.kt`

**关键迁移点**：
- `dart:io HttpServer` → `com.sun.net.httpserver.HttpServer`（JVM 内置，Android/Desktop 通用）
- `Dio` CDN 代理 → Ktor HttpClient 流式请求
- Range 请求解析直接翻译（纯逻辑）
- 边播边缓存：逐 chunk 转发 + 512KB 分段写入

**验证**：编译通过 + 单元测试（Range 解析、代理路由）

---

## Task 9: PreloadService（任务 2.8）

**依赖**：Task 7 完成（需要 VideoCacheService）

**目标**：迁移预加载服务，含动态深度计算、取消/回收机制

**文件清单**：
- 新建 `shared/src/commonMain/kotlin/com/mediamix/shared/services/PreloadService.kt`（~760行）
- 新建测试：`shared/src/commonTest/kotlin/com/mediamix/shared/services/PreloadServiceTest.kt`

**关键迁移点**：
- `PreloadDepthCalculator` 纯逻辑直接翻译
- `PreloadPriority` / `PreloadTaskStatus` 枚举
- 并发控制：Dart `Semaphore` → `kotlinx.coroutines.sync.Semaphore`
- 取消机制：Dart `Timer` → Kotlin `Job.cancel()`
- Dio → Ktor HttpClient

**验证**：编译通过 + 单元测试

---

## Task 10: 集成验证

**依赖**：Task 2-9 全部完成

**目标**：全量构建验证 + Koin DI 集成 + 关键流程测试

**验证项**：
1. `./gradlew build` 全量构建通过
2. `./gradlew :shared:allTests` 全部单元测试通过
3. Koin DI 模块完整性检查（所有服务可注入）
4. 蜘蛛引擎端到端测试：TvBoxConfig 解析 → 蜘蛛创建 → 首页获取（Mock HTTP）
5. 缓存系统端到端测试：写入 → 读取 → 淘汰 → 策略建议

---

## 并行执行策略

| 波次 | 并行任务 | 说明 |
|------|---------|------|
| Wave 1 | Task 1（模型+网络基础） | 前置，必须先完成 |
| Wave 2 | Task 2 + Task 3 + Task 4 + Task 6 + Task 7 | 5 个任务并行（蜘蛛/JavaBridge/配置解析/缓存策略/缓存核心） |
| Wave 3 | Task 5 + Task 8 + Task 9 | Registry+Service / LocalProxy / Preload |
| Wave 4 | Task 10 | 集成验证 |

**注意**：Task 7 依赖 Task 6（CacheStrategyManager 集成），Wave 2 中 Task 7 需等 Task 6 完成后启动。实际并行为：
- Wave 2a: Task 2 + Task 3 + Task 4 + Task 6
- Wave 2b: Task 7（等 Task 6 完成）
- Wave 3: Task 5 + Task 8 + Task 9

---

## 新增依赖

需要在 `libs.versions.toml` 中添加：
- `okio`（跨平台文件 IO，用于 DiskCache）— 可选，也可直接用 `java.io.File`
- `kotlinx-datetime`（类型安全时间处理）— 可选

现有依赖已覆盖：Ktor Client、kotlinx-serialization、Koin、jsoup、multiplatform-settings、kermit

---

## 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| VideoApiService 801行迁移复杂 | 拆分为 VideoApiService + DnsCache + PrefetchCache 三个文件 |
| LocalProxyServer 流式代理 | 先实现基本代理功能，边播边缓存可分步完善 |
| JavaBridgeManager Android 兼容性 | Android 端可用 URLClassLoader（ART 兼容 Java 9+），若不可行退回 DexClassLoader |
| TvBoxSite 模型修改影响范围 | 仅 SpiderModels.kt 一个文件，且阶段二刚开始，影响可控 |

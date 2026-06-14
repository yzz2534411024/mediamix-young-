# MediaMix - 跨平台媒体聚合应用

一款基于 Flutter 开发的跨平台视频聚合播放应用，支持多源视频采集、在线播放、下载管理等功能，内置全面的播放性能优化体系。

## 功能特性

### 核心功能
- **多源视频聚合** — 支持添加多个 CMS 视频源，自动聚合搜索结果
- **在线播放** — 基于 media_kit 的高性能视频播放器，支持硬解码
- **换源播放** — 播放中一键切换不同源的同名视频
- **下载管理** — 支持视频离线下载与后台管理
- **播放记忆** — 自动保存播放进度，下次继续观看
- **直播电视** — 支持 IPTV 直播源导入与播放

### 播放器优化（v1.0 新增）
- **接口解析优化** — DNS 预解析、HTTPDNS、接口预请求与并行化、CDN 调度、指数退避重试
- **视频解码优化** — 硬解码优先 + 自动降级、解码器配置优化
- **播放流畅性** — ABR 自适应码率、动态缓冲水位线、Seek 关键帧优化、音视频同步监控
- **加载缓存** — 四级缓存架构（L1帧缓存/L2码流/L3完整视频/L4分片）、LRU+优先级淘汰、智能预加载
- **倍速播放** — 0.25x 步进、高倍速优化
- **画中画** — 支持 PiP 模式，后台继续播放音频
- **功耗管理** — 三档功耗模式（全性能/均衡/省电），电池电量自动切换
- **性能监控** — 11 个埋点事件、QoE/QoS 双维度指标、实时告警

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.x / Dart 3.x |
| 状态管理 | Riverpod |
| 数据库 | Drift (SQLite) |
| 网络请求 | Dio |
| 视频播放 | media_kit + media_kit_video |
| 路由 | GoRouter |
| 响应式布局 | flutter_screenutil |

## 项目结构

```
lib/
├── main.dart                          # 应用入口，服务初始化
├── app/
│   └── router.dart                    # 路由配置
├── core/
│   ├── database/                      # Drift 数据库
│   │   ├── database.dart              # 数据库定义
│   │   ├── database.g.dart            # 生成代码
│   │   └── database_provider.dart     # 数据库 Provider
│   ├── network/
│   │   └── network_engine.dart        # 高性能网络引擎（带宽估算/缓存/重试/DNS预解析）
│   └── services/
│       ├── player_metrics_service.dart # 播放性能监控服务
│       ├── video_cache_service.dart    # 多级视频缓存服务
│       ├── preload_service.dart        # 智能预加载服务
│       ├── power_manager_service.dart  # 功耗管理服务
│       ├── download_service.dart       # 下载服务
│       ├── cache_service.dart          # 通用缓存服务
│       └── theme_provider.dart         # 主题管理
├── features/
│   ├── video/
│   │   ├── models/video_models.dart   # 视频数据模型
│   │   ├── services/
│   │   │   ├── tbox_api_service.dart   # 视频 API 服务（DNS预解析/并行请求/CDN调度）
│   │   │   └── subtitle_service.dart   # 字幕服务（二分查找/多轨道/精确同步）
│   │   ├── providers/video_providers.dart # Riverpod Providers
│   │   └── pages/
│   │       ├── player_page.dart        # 播放器页面（全链路优化集成）
│   │       ├── video_home_page.dart    # 视频首页
│   │       └── video_detail_page.dart  # 视频详情页
│   ├── settings/                       # 设置页面
│   └── live/                           # 直播功能
└── assets/
    └── icons/icon.png                  # 应用图标源文件
```

## 快速开始

### 环境要求

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android Studio / VS Code
- Android SDK (API 21+)
- iOS: Xcode 15+ (如需 iOS 构建)

### 安装与运行

```bash
# 1. 克隆项目
git clone <repository-url>
cd mediamix

# 2. 获取依赖
flutter pub get

# 3. 生成数据库代码（如修改了 database.dart）
flutter pub run build_runner build --delete-conflicting-outputs

# 4. 运行应用
flutter run

# 5. 构建 APK
flutter build apk --release
```

### 生成应用图标

如需更换应用图标，替换 `assets/icons/icon.png` 后运行：

```bash
dart run flutter_launcher_icons
```

## 播放器优化架构

### 接口解析优化链路

```
用户点击 → DNS预解析(省100-200ms) → 接口预请求(省300-500ms)
         → 并行换源请求 → CDN调度 → 开始播放
```

### 四级缓存架构

```
┌─ L1: 内存帧缓存 (纳秒级, 20条目) ─────────────┐
├─ L2: 内存码流缓存 (纳秒级, 50条目) ────────────┤
├─ L3: 磁盘完整视频缓存 (毫秒级, ≤2GB) ──────────┤
└─ L4: 磁盘分片缓存 (毫秒级, HLS/DASH segments) ─┘
```

### ABR 自适应码率

| 条件 | 动作 |
|------|------|
| 缓冲 < 5s | 立即降级画质 |
| 缓冲 > 30s 且带宽充足 5s | 升级画质 |
| 切换间隔 < 10s | 不切换 |

### 功耗模式

| 模式 | 帧率 | 分辨率 | 预加载 | 弹幕 |
|------|------|--------|--------|------|
| 全性能 | 60fps | 1080p | 开启 | 开启 |
| 均衡 | 30fps | 720p | 开启 | 开启 |
| 省电 | 24fps | 480p | 关闭 | 关闭 |

## 性能监控指标

| 指标 | 目标 | 告警阈值 |
|------|------|---------|
| 首屏时间 | ≤ 1.5s | > 3s |
| 卡顿率 | ≤ 1% | > 3% |
| 缓存命中率 | ≥ 85% | < 70% |
| Seek 延迟 | ≤ 1s | > 2s |

## 常用开发命令

```bash
# 代码分析
flutter analyze

# 运行测试
flutter test

# 生成数据库代码（持续监听）
flutter pub run build_runner watch

# 清理构建缓存
flutter clean && flutter pub get

# 格式化代码
dart format lib/
```

## 许可证

本项目仅供学习交流使用。

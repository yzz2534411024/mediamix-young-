import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:media_kit/media_kit.dart';
import 'app/router.dart';
import 'core/services/theme_provider.dart';
import 'core/services/video_cache_service.dart';
import 'core/services/player_metrics_service.dart';
import 'core/services/power_manager_service.dart';
import 'core/services/data_reporter_service.dart';
import 'core/services/metrics_collector_service.dart';
import 'core/services/cache_strategy_manager.dart';
import 'core/database/database.dart';
import 'features/video/models/video_models.dart';
import 'core/services/privacy_manager_service.dart';
import 'core/network/network_engine.dart';
import 'core/network/proxy_config_service.dart';
import 'core/services/local_proxy_server.dart';
import 'core/widgets/privacy_consent_dialog.dart';
import 'features/video/services/spider/java_bridge_manager.dart';
import 'features/video/services/spider/spider_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 初始化关键服务（单个失败不影响启动）
  await _initCriticalServices();

  runApp(const ProviderScope(child: YoungApp()));
}

/// 初始化关键服务 — 并行初始化关键路径服务，非关键服务懒加载
///
/// 关键路径服务（并行初始化）：
///   - VideoCacheService：磁盘 I/O，播放核心依赖
///   - PrivacyManagerService：隐私授权状态，UI 立即需要
///   - ProxyConfigService：网络代理配置，网络请求依赖
///
/// 懒加载服务（首次使用时初始化）：
///   - PowerManagerService、MetricsCollectorService、
///     DataReporterService、DeviceCapabilityService
Future<void> _initCriticalServices() async {
  // 并行初始化关键路径服务
  await Future.wait([
    // 视频缓存服务
    () async {
      try {
        await VideoCacheService.instance.initialize();
      } catch (e) {
        debugPrint('缓存服务初始化失败: $e');
      }
    }(),
    // 隐私管理服务
    () async {
      try {
        await PrivacyManagerService.instance.initialize();
      } catch (e) {
        debugPrint('隐私管理服务初始化失败: $e');
      }
    }(),
    // 代理配置
    () async {
      try {
        await ProxyConfigService.instance.initialize();
      } catch (e) {
        debugPrint('代理配置初始化失败: $e');
      }
    }(),
  ]);

  // Java Bridge 蜘蛛引擎初始化（非阻塞，保持原有逻辑）
  try {
    final bridgeManager = JavaBridgeManager.instance;
    // 尝试从内置 TVBox 源获取蜘蛛 JAR 并启动 Bridge
    for (final site in CmsApiSite.defaultSites) {
      if (site.isTvBox) {
        final spiderService = SpiderService();
        try {
          final config = await spiderService
              .fetchTvBoxConfig(site.apiUrl)
              .timeout(const Duration(seconds: 15));
          final started = await bridgeManager.initialize(
            spiderJarUrl: config.spiderUrl,
          );
          if (started) {
            debugPrint('Java Bridge 已启动 (通过 ${site.name})');
          } else {
            debugPrint('Java Bridge 启动失败，csp_* 蜘蛛将不可用');
          }
        } catch (e) {
          debugPrint('Java Bridge 初始化异常: $e');
        } finally {
          spiderService.close();
        }
        break; // 只尝试第一个 TVBox 源
      }
    }
  } catch (e) {
    debugPrint('Java Bridge 初始化失败: $e');
  }
}

/// 异步预热任务 — 不阻塞启动，在 UI 渲染后执行
void _warmupAsyncTasks() {
  // DNS 预解析：后台异步执行，不阻塞UI
  try {
    final engine = NetworkEngine.instance;
    final builtinUrls =
        CmsApiSite.defaultSites.map((s) {
          final uri = Uri.parse(s.apiUrl);
          return '${uri.scheme}://${uri.host}';
        }).toSet().toList();
    engine.preResolveDns(builtinUrls);
  } catch (e) {
    debugPrint('DNS 预解析失败: $e');
  }
}

class YoungApp extends ConsumerStatefulWidget {
  const YoungApp({super.key});

  @override
  ConsumerState<YoungApp> createState() => _YoungAppState();
}

class _YoungAppState extends ConsumerState<YoungApp> {
  bool _hasCheckedConsent = false;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (_, child) {
        // 首次启动检查隐私授权
        if (!_hasCheckedConsent) {
          _hasCheckedConsent = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkPrivacyConsent();
            _warmupAsyncTasks();
          });
        }

        return MaterialApp.router(
          title: 'Young',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF6750A4),
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF6750A4),
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          themeMode: themeMode,
          routerConfig: router,
        );
      },
    );
  }

  /// 检查是否需要显示首次隐私授权弹窗
  Future<void> _checkPrivacyConsent() async {
    final privacy = PrivacyManagerService.instance;
    if (privacy.shouldShowConsentDialog && mounted) {
      await PrivacyConsentDialog.show(context);
    }
  }

  @override
  void dispose() {
    // 停止本地代理服务器
    LocalProxyServer.instance.stop();

    // 关闭 Java Bridge 进程
    JavaBridgeManager.instance.shutdown();

    // 释放单例服务资源（StreamController、Timer、Subscription）
    VideoCacheService.instance.dispose();
    PlayerMetricsService.instance.dispose();
    PowerManagerService.instance.dispose();
    DataReporterService.instance.dispose();
    MetricsCollectorService.instance.dispose();
    PrivacyManagerService.instance.dispose();
    CacheStrategyManager.instance.dispose();
    NetworkEngine.instance.dispose();

    // 关闭数据库连接
    AppDatabase.instance.close();

    super.dispose();
  }
}

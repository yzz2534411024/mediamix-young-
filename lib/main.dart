import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:media_kit/media_kit.dart';
import 'app/router.dart';
import 'core/services/theme_provider.dart';
import 'core/services/video_cache_service.dart';
import 'features/video/models/video_models.dart';
import 'core/services/power_manager_service.dart';
import 'core/services/privacy_manager_service.dart';
import 'core/services/metrics_collector_service.dart';
import 'core/services/data_reporter_service.dart';
import 'core/database/database_provider.dart';
import 'core/database/database.dart';
import 'core/network/network_engine.dart';
import 'core/network/proxy_config_service.dart';
import 'core/services/device_capability_service.dart';
import 'core/services/local_proxy_server.dart';
import 'core/widgets/privacy_consent_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 初始化关键服务（单个失败不影响启动）
  await _initCriticalServices();

  runApp(const ProviderScope(child: YoungApp()));
}

/// 初始化关键服务 — 每个服务独立 try-catch，任一个失败都不阻塞启动
Future<void> _initCriticalServices() async {
  // 视频缓存服务
  try {
    await VideoCacheService.instance.initialize();
  } catch (e) {
    debugPrint('缓存服务初始化失败: $e');
  }

  // 功耗管理服务
  try {
    await PowerManagerService.instance.initialize();
  } catch (e) {
    debugPrint('功耗管理服务初始化失败: $e');
  }

  // 隐私管理服务
  try {
    await PrivacyManagerService.instance.initialize();
  } catch (e) {
    debugPrint('隐私管理服务初始化失败: $e');
  }

  // 指标采集和数据上报
  try {
    MetricsCollectorService.instance.initialize(AppDatabase.instance);
    await DataReporterService.instance.initialize(AppDatabase.instance);
  } catch (e) {
    debugPrint('指标服务初始化失败: $e');
  }

  // 代理配置和设备能力检测
  try {
    await ProxyConfigService.instance.initialize();
    await DeviceCapabilityService.instance.getCapabilityReport();
  } catch (e) {
    debugPrint('代理/设备检测初始化失败: $e');
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
    LocalProxyServer.instance.stop();
    super.dispose();
  }
}

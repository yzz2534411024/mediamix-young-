import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:media_kit/media_kit.dart';
import 'app/router.dart';
import 'core/services/theme_provider.dart';
import 'core/services/video_cache_service.dart';
import 'core/services/power_manager_service.dart';
import 'core/services/privacy_manager_service.dart';
import 'core/services/metrics_collector_service.dart';
import 'core/services/data_reporter_service.dart';
import 'core/database/database_provider.dart';
import 'core/database/database.dart';
import 'core/network/network_engine.dart';
import 'core/widgets/privacy_consent_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 初始化优化服务
  await _initializeServices();

  runApp(const ProviderScope(child: MediaMixApp()));
}

/// 初始化所有优化服务
Future<void> _initializeServices() async {
  // 初始化视频缓存服务
  try {
    await VideoCacheService.instance.initialize();
  } catch (e) {
    // 缓存服务初始化失败不影响启动
    debugPrint('视频缓存服务初始化失败: $e');
  }

  // 初始化功耗管理服务
  try {
    await PowerManagerService.instance.initialize();
  } catch (e) {
    debugPrint('功耗管理服务初始化失败: $e');
  }

  // 初始化隐私管理服务
  try {
    await PrivacyManagerService.instance.initialize();
  } catch (e) {
    debugPrint('隐私管理服务初始化失败: $e');
  }

  // 初始化指标采集和数据上报服务（需要数据库实例）
  try {
    // 创建临时数据库实例用于初始化
    final db = AppDatabase();
    MetricsCollectorService.instance.initialize(db);
    DataReporterService.instance.initialize(db);
  } catch (e) {
    debugPrint('指标服务初始化失败: $e');
  }

  // DNS 预解析：提前解析内置站点域名
  try {
    final engine = NetworkEngine.instance;
    final builtinUrls = [
      'https://bfzyapi.com',
      'https://cjhd.lziapi.com',
      'https://cjhd.ffzyapi.com',
      'http://api.1080zyku.com',
      'http://hongniuzy2.com',
    ];
    await engine.preResolveDns(builtinUrls);
  } catch (e) {
    debugPrint('DNS 预解析失败: $e');
  }
}

class MediaMixApp extends ConsumerStatefulWidget {
  const MediaMixApp({super.key});

  @override
  ConsumerState<MediaMixApp> createState() => _MediaMixAppState();
}

class _MediaMixAppState extends ConsumerState<MediaMixApp> {
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
          });
        }

        return MaterialApp.router(
          title: 'MediaMix',
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
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:media_kit/media_kit.dart';
import 'app/router.dart';
import 'core/services/theme_provider.dart';
import 'core/services/video_cache_service.dart';
import 'core/services/power_manager_service.dart';
import 'core/network/network_engine.dart';

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

class MediaMixApp extends ConsumerWidget {
  const MediaMixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (_, child) {
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
}

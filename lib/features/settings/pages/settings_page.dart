import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../video/providers/video_providers.dart';
import '../../video/models/video_models.dart';
import '../../../core/services/theme_provider.dart';
import '../../../core/services/privacy_manager_service.dart';
import '../../../core/services/data_reporter_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // 解码模式：0=自动, 1=硬件优先, 2=软件优先
  int _decodeMode = 0;

  static const _decodeModeLabels = ['自动', '硬件优先', '软件优先'];
  static const _themeModeLabels = ['跟随系统', '浅色模式', '深色模式'];

  // 隐私偏好
  bool _metricsEnabled = false;
  bool _performanceDataEnabled = true;
  bool _wifiOnlyUpload = true;
  Map<String, dynamic> _localDataSummary = {};

  @override
  void initState() {
    super.initState();
    _loadPrivacyPrefs();
  }

  Future<void> _loadPrivacyPrefs() async {
    final prefs = PrivacyManagerService.instance.preferences;
    setState(() {
      _metricsEnabled = prefs.metricsEnabled;
      _performanceDataEnabled = prefs.performanceDataEnabled;
      _wifiOnlyUpload = prefs.wifiOnlyUpload;
    });
    _refreshDataSummary();
  }

  Future<void> _refreshDataSummary() async {
    final summary = await DataReporterService.instance.getLocalDataSummary();
    if (mounted) {
      setState(() {
        _localDataSummary = summary;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(cmsSiteListProvider);
    final currentSite = ref.watch(currentSiteProvider);
    final themeMode = ref.watch(themeModeProvider);
    final themeOption = ref.read(themeModeProvider.notifier).currentOption;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 数据源管理
          _SectionHeader(title: '数据源'),
          ListTile(
            leading: const Icon(Icons.source),
            title: const Text('数据源管理'),
            subtitle: Text('${sites.where((s) => s.enabled).length}/${sites.length} 个源已启用'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/source-manage'),
          ),
          const Divider(),
          // 通用设置
          _SectionHeader(title: '通用'),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('下载管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/downloads'),
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('解码模式'),
            subtitle: Text(_decodeModeLabels[_decodeMode]),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDecodeModeDialog(),
          ),
          ListTile(
            leading: Icon(
              themeOption == ThemeModeOption.dark
                  ? Icons.dark_mode
                  : themeOption == ThemeModeOption.light
                      ? Icons.light_mode
                      : Icons.brightness_auto,
            ),
            title: const Text('主题设置'),
            subtitle: Text(_themeModeLabels[themeOption.index]),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemeModeDialog(),
          ),
          const Divider(),
          // 隐私与数据
          _SectionHeader(title: '隐私与数据'),
          SwitchListTile(
            secondary: Icon(
              _metricsEnabled ? Icons.analytics : Icons.analytics_outlined,
            ),
            title: const Text('使用数据分享'),
            subtitle: Text(_metricsEnabled ? '已开启 — 帮助改善应用体验' : '已关闭'),
            value: _metricsEnabled,
            onChanged: (value) async {
              await PrivacyManagerService.instance.setMetricsEnabled(value);
              setState(() => _metricsEnabled = value);
            },
          ),
          if (_metricsEnabled) ...[
            SwitchListTile(
              secondary: const Icon(Icons.speed),
              title: const Text('性能数据'),
              subtitle: const Text('首屏时间、卡顿率、Seek延迟等'),
              value: _performanceDataEnabled,
              onChanged: (value) async {
                await PrivacyManagerService.instance.setPerformanceDataEnabled(value);
                setState(() => _performanceDataEnabled = value);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.wifi),
              title: const Text('仅 WiFi 下上报'),
              subtitle: const Text('移动网络下不上报数据'),
              value: _wifiOnlyUpload,
              onChanged: (value) async {
                await PrivacyManagerService.instance.setWifiOnlyUpload(value);
                setState(() => _wifiOnlyUpload = value);
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('本地数据'),
            subtitle: Text(
              '会话 ${_localDataSummary['total_sessions'] ?? 0} 条，'
              '事件 ${_localDataSummary['total_events'] ?? 0} 条'
              '${_localDataSummary['unuploaded_sessions'] != null && _localDataSummary['unuploaded_sessions'] > 0
                  ? '（待上报 ${_localDataSummary['unuploaded_sessions']} 条）' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLocalDataDialog(),
          ),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('导出数据'),
            subtitle: const Text('导出使用数据和性能数据为JSON文件'),
            onTap: () => _exportData(),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('立即上报'),
            subtitle: const Text('手动触发数据上报'),
            onTap: () async {
              final result = await DataReporterService.instance.uploadNow();
              if (mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_getUploadResultText(result)),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                _refreshDataSummary();
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Young',
                applicationVersion: '0.2.0',
                children: [
                  const Text('跨平台视频点播应用'),
                ],
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 3,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.movie), label: '视频'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
        onDestinationSelected: (index) {
          if (index == 0) context.go('/video');
          if (index == 1) context.go('/history');
          if (index == 2) context.go('/favorite');
        },
      ),
    );
  }

  String _getUploadResultText(UploadResult result) {
    switch (result) {
      case UploadResult.success:
        return '数据上报成功';
      case UploadResult.networkUnavailable:
        return '网络不可用，稍后重试';
      case UploadResult.privacyBlocked:
        return '隐私设置已关闭上报';
      case UploadResult.failed:
        return '上报失败，稍后自动重试';
      case UploadResult.noData:
        return '暂无待上报数据';
    }
  }

  /// 导出数据到 JSON 文件并分享
  Future<void> _exportData() async {
    final path = await DataReporterService.instance.exportDataToFile();
    if (!mounted) return;

    if (path != null) {
      try {
        await Share.shareXFiles([XFile(path)], text: 'Young 数据导出');
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('数据导出成功'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('分享失败: $e'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('导出数据失败，请稍后重试'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 显示本地数据详情对话框
  void _showLocalDataDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('本地数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('会话记录: ${_localDataSummary['total_sessions'] ?? 0} 条'),
            Text('事件记录: ${_localDataSummary['total_events'] ?? 0} 条'),
            const SizedBox(height: 8),
            Text(
              '待上报会话: ${_localDataSummary['unuploaded_sessions'] ?? 0} 条',
              style: const TextStyle(color: Colors.orange),
            ),
            Text(
              '待上报事件: ${_localDataSummary['unuploaded_events'] ?? 0} 条',
              style: const TextStyle(color: Colors.orange),
            ),
            const SizedBox(height: 16),
            const Text(
              '数据说明：\n'
              '· 性能数据：首屏时间、卡顿率等\n'
              '· 使用数据：观看时长、操作频次\n'
              '· 不采集任何个人身份信息\n'
              '· 数据仅用于改善应用体验',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showClearDataConfirmDialog();
            },
            child: const Text('清除本地数据', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 显示清除数据确认对话框
  void _showClearDataConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除所有本地指标数据吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await DataReporterService.instance.clearAllLocalData();
              if (mounted) {
                Navigator.pop(ctx);
                _refreshDataSummary();
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('本地数据已清除'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('确认清除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 显示解码模式选择对话框
  void _showDecodeModeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择解码模式'),
        children: List.generate(_decodeModeLabels.length, (index) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _decodeMode = index);
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Icon(
                  _decodeMode == index
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _decodeMode == index
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 12),
                Text(_decodeModeLabels[index]),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// 显示主题模式选择对话框
  void _showThemeModeDialog() {
    final notifier = ref.read(themeModeProvider.notifier);
    final currentOption = notifier.currentOption;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择主题模式'),
        children: ThemeModeOption.values.map((option) {
          final isSelected = option == currentOption;
          return SimpleDialogOption(
            onPressed: () {
              notifier.setThemeMode(option);
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
                const SizedBox(width: 12),
                Icon(_getThemeIcon(option), size: 20),
                const SizedBox(width: 8),
                Text(_themeModeLabels[option.index]),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _getThemeIcon(ThemeModeOption option) {
    switch (option) {
      case ThemeModeOption.system:
        return Icons.brightness_auto;
      case ThemeModeOption.light:
        return Icons.light_mode;
      case ThemeModeOption.dark:
        return Icons.dark_mode;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../video/providers/video_providers.dart';
import '../../video/models/video_models.dart';
import '../../../core/services/theme_provider.dart';

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
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'MediaMix',
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

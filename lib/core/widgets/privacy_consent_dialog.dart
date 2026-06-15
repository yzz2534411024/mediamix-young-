import 'package:flutter/material.dart';
import '../services/privacy_manager_service.dart';

/// 首次隐私授权弹窗
///
/// 首次安装后第一次打开 App 时弹出，询问用户是否同意分享使用数据
class PrivacyConsentDialog extends StatelessWidget {
  const PrivacyConsentDialog({super.key});

  /// 显示授权弹窗，返回 true 表示同意
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PrivacyConsentDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.security, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            const Text('帮助改善 MediaMix'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '我们希望采集一些匿名使用数据来改善您的体验，包括：',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 16),
            _DataItem(
              icon: Icons.speed,
              title: '性能数据',
              description: '首屏加载时间、卡顿率、Seek延迟',
            ),
            SizedBox(height: 12),
            _DataItem(
              icon: Icons.timeline,
              title: '使用习惯数据',
              description: '观看时长、操作频次',
            ),
            SizedBox(height: 16),
            Divider(),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.shield, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '不采集任何个人身份信息\n数据仅用于改善应用体验\n可随时在设置中关闭',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await PrivacyManagerService.instance.denyConsent();
              if (context.mounted) Navigator.pop(context, false);
            },
            child: const Text('暂不开启'),
          ),
          FilledButton(
            onPressed: () async {
              await PrivacyManagerService.instance.grantConsent();
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('同意并分享'),
          ),
        ],
      ),
    );
  }
}

class _DataItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _DataItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}

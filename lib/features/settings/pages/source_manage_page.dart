import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../video/providers/video_providers.dart';
import '../../video/models/video_models.dart';

class SourceManagePage extends ConsumerStatefulWidget {
  const SourceManagePage({super.key});

  @override
  ConsumerState<SourceManagePage> createState() => _SourceManagePageState();
}

class _SourceManagePageState extends ConsumerState<SourceManagePage> {
  bool _isChecking = false;

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(cmsSiteListProvider);
    final statusMap = ref.watch(sourceStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据源管理'),
        actions: [
          // 检测全部
          IconButton(
            icon: _isChecking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            tooltip: '检测全部',
            onPressed: _isChecking ? null : _checkAll,
          ),
          // 添加源
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加源',
            onPressed: _showAddSourceDialog,
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: sites.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final site = sites[index];
          final status = statusMap[site.key];
          return _SourceTile(
            site: site,
            status: status,
            onToggle: () => ref.read(sourceActionsProvider).toggleSourceEnabled(site.key),
            onDelete: site.isBuiltIn ? null : () => _confirmDelete(site),
            onCheck: () => _checkSingle(site),
          );
        },
      ),
    );
  }

  Future<void> _checkAll() async {
    setState(() => _isChecking = true);
    await ref.read(sourceActionsProvider).checkAllSources();
    if (mounted) setState(() => _isChecking = false);
  }

  Future<void> _checkSingle(CmsApiSite site) async {
    final status = await ref.read(sourceActionsProvider).checkSource(site);
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status.isAvailable
              ? '${site.name} 可用 (${status.latencyMs}ms)'
              : '${site.name} 不可用: ${status.error ?? "连接失败"}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmDelete(CmsApiSite site) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除数据源'),
        content: Text('确定要删除「${site.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(sourceActionsProvider).removeSource(site.key);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddSourceDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    bool isValidating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加数据源'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '源名称',
                  hintText: '如：我的资源站',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'API 地址',
                  hintText: '如：https://example.com/api.php/provide/vod/',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: isValidating ? null : () async {
                final name = nameController.text.trim();
                final url = urlController.text.trim();
                if (name.isEmpty || url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请填写完整信息'), behavior: SnackBarBehavior.floating),
                  );
                  return;
                }
                setDialogState(() => isValidating = true);
                // 先验证
                final site = CmsApiSite(
                  key: 'custom_${const Uuid().v4().substring(0, 8)}',
                  name: name,
                  apiUrl: url,
                );
                final status = await ref.read(sourceActionsProvider).checkSource(site);
                setDialogState(() => isValidating = false);
                if (status.isAvailable) {
                  ref.read(sourceActionsProvider).addSource(site);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('添加成功！延迟 ${status.latencyMs}ms'), behavior: SnackBarBehavior.floating),
                    );
                  }
                } else {
                  // 验证失败，询问是否仍然添加
                  if (mounted) {
                    final shouldAdd = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('验证失败'),
                        content: Text('该源无法连接：${status.error ?? "未知错误"}\n\n是否仍然添加？'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('仍然添加')),
                        ],
                      ),
                    );
                    if (shouldAdd == true) {
                      ref.read(sourceActionsProvider).addSource(site);
                      Navigator.pop(ctx);
                    }
                  }
                }
              },
              child: isValidating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('验证并添加'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final CmsApiSite site;
  final SourceStatus? status;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;
  final VoidCallback onCheck;

  const _SourceTile({
    required this.site,
    this.status,
    required this.onToggle,
    this.onDelete,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(site.key),
      direction: onDelete != null ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete?.call();
        return false; // 手动处理删除
      },
      child: ListTile(
        leading: _buildStatusIcon(),
        title: Row(
          children: [
            Expanded(child: Text(site.name)),
            if (site.isBuiltIn)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('内置', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(site.apiUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            if (status != null)
              Text(
                status!.isAvailable ? '可用 · ${status!.latencyMs}ms' : '不可用',
                style: TextStyle(
                  fontSize: 11,
                  color: status!.isAvailable ? Colors.green : Colors.red,
                ),
              ),
          ],
        ),
        trailing: Switch(
          value: site.enabled,
          onChanged: (_) => onToggle(),
        ),
        onLongPress: onCheck,
      ),
    );
  }

  Widget _buildStatusIcon() {
    if (status == null) {
      return const Icon(Icons.cloud_outlined, color: Colors.grey);
    }
    if (status!.isAvailable) {
      if (status!.latencyMs < 500) {
        return const Icon(Icons.cloud_done, color: Colors.green);
      } else if (status!.latencyMs < 2000) {
        return const Icon(Icons.cloud_queue, color: Colors.orange);
      } else {
        return const Icon(Icons.cloud_queue, color: Colors.deepOrange);
      }
    }
    return const Icon(Icons.cloud_off, color: Colors.red);
  }
}

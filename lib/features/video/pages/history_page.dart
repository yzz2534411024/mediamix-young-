import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/video_providers.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(watchHistoryProvider);
    final actions = ref.read(watchHistoryActionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('观看历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空历史',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清空历史'),
                  content: const Text('确定要清空所有观看历史吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    FilledButton(
                      onPressed: () {
                        actions.clearAllHistory();
                        Navigator.pop(ctx);
                      },
                      child: const Text('清空'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: historyAsync.when(
        data: (histories) {
          if (histories.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('暂无观看记录', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: histories.length,
            itemBuilder: (context, index) {
              final h = histories[index];
              return Dismissible(
                key: Key(h.vodId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => actions.deleteHistory(h.vodId),
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 50,
                        height: 70,
                        child: h.vodPic != null && h.vodPic!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: h.vodPic!,
                                fit: BoxFit.cover,
                                memCacheWidth: 100,
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.movie, color: Colors.grey, size: 20),
                                ),
                              )
                            : Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.movie, color: Colors.grey, size: 20),
                              ),
                      ),
                    ),
                    title: Text(h.vodName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      '${h.episodeName ?? ''} · ${_formatTime(h.lastWatchTime)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    onTap: () {
                      context.push('/detail?vodId=${Uri.encodeComponent(h.vodId)}&sourceKey=${Uri.encodeComponent(h.sourceKey)}');
                    },
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.movie), label: '视频'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
        onDestinationSelected: (index) {
          if (index == 0) context.go('/video');
          if (index == 2) context.go('/favorite');
          if (index == 3) context.go('/settings');
        },
      ),
    );
  }

  String _formatTime(int timestamp) {
    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }
}

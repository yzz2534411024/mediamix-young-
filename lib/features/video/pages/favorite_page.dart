import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/video_providers.dart';

class FavoritePage extends ConsumerWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favAsync = ref.watch(favoriteListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: favAsync.when(
        data: (favorites) {
          if (favorites.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('暂无收藏', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('在影片详情页点击心形图标收藏', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.58,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final fav = favorites[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: InkWell(
                  onTap: () {
                    context.push('/detail?vodId=${Uri.encodeComponent(fav.vodId)}&sourceKey=${Uri.encodeComponent(fav.sourceKey)}');
                  },
                  onLongPress: () {
                    // 长按取消收藏
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('取消收藏'),
                        content: Text('确定取消收藏「${fav.vodName}」吗？'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                          FilledButton(
                            onPressed: () {
                              ref.read(favoriteActionsProvider).removeFavorite(fav.vodId);
                              Navigator.pop(ctx);
                            },
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: fav.vodPic != null && fav.vodPic!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: fav.vodPic!,
                                fit: BoxFit.cover,
                                memCacheWidth: 300,
                                placeholder: (_, __) => Container(
                                  color: Colors.grey[200],
                                  child: const Center(child: Icon(Icons.movie, color: Colors.grey, size: 32)),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey[200],
                                  child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 32)),
                                ),
                              )
                            : Container(
                                color: Colors.grey[200],
                                child: const Center(child: Icon(Icons.movie, color: Colors.grey, size: 32)),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          fav.vodName,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
        selectedIndex: 2,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.movie), label: '视频'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
        onDestinationSelected: (index) {
          if (index == 0) context.go('/video');
          if (index == 1) context.go('/history');
          if (index == 3) context.go('/settings');
        },
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/video_providers.dart';
import '../models/video_models.dart';

class VideoSearchPage extends ConsumerStatefulWidget {
  const VideoSearchPage({super.key});

  @override
  ConsumerState<VideoSearchPage> createState() => _VideoSearchPageState();
}

class _VideoSearchPageState extends ConsumerState<VideoSearchPage> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// 防抖搜索（500ms）
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    setState(() {}); // 更新清除按钮显示
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      ref.read(debouncedSearchQueryProvider.notifier).state = query.trim();
    });
  }

  /// 立即搜索
  void _doSearch(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    ref.read(debouncedSearchQueryProvider.notifier).state = trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final searchResultAsync = ref.watch(searchResultProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索影片（全站搜索）...',
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _debounceTimer?.cancel();
                      ref.read(debouncedSearchQueryProvider.notifier).state = '';
                      setState(() {});
                    },
                  )
                : null,
          ),
          onChanged: _onSearchChanged,
          onSubmitted: _doSearch,
        ),
      ),
      body: ref.watch(debouncedSearchQueryProvider).isEmpty
          ? _buildEmptyState()
          : searchResultAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text('搜索失败', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    Text('$e', style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              data: (data) {
                if (data.list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('未找到相关影片', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: data.list.length,
                  itemBuilder: (context, index) {
                    final item = data.list[index];
                    final sites = ref.read(cmsSiteListProvider);
                    final sourceKey = item.sourceKey ?? (sites.isNotEmpty ? sites.first.key : '');
                    return _SearchResultItem(item: item, sourceKey: sourceKey);
                  },
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('输入关键词搜索影片', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          const SizedBox(height: 8),
          Text('将同时搜索所有站点', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        ],
      ),
    );
  }
}

/// 搜索结果项
class _SearchResultItem extends StatelessWidget {
  final VideoItem item;
  final String sourceKey;

  const _SearchResultItem({required this.item, required this.sourceKey});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          context.push('/detail?vodId=${Uri.encodeComponent(item.vodId)}&sourceKey=${Uri.encodeComponent(sourceKey)}');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 60,
                  height: 80,
                  child: item.vodPic != null && item.vodPic!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.vodPic!,
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                          placeholder: (_, __) => Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.movie, color: Colors.grey, size: 24),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image, color: Colors.grey, size: 24),
                          ),
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.movie, color: Colors.grey, size: 24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.vodName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (item.typeName != null && item.typeName!.isNotEmpty)
                      Text(item.typeName!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (item.vodYear != null && item.vodYear!.isNotEmpty)
                      Text(item.vodYear!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    if (item.vodRemarks != null && item.vodRemarks!.isNotEmpty)
                      Text(item.vodRemarks!, style: TextStyle(fontSize: 11, color: Colors.orange[700])),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

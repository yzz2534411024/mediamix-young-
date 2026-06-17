import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database.dart';
import '../../../core/services/download_service.dart';
import '../../video/providers/video_providers.dart';

class DownloadPage extends ConsumerWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(downloadTasksProvider);
    final downloadService = ref.read(downloadServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            tooltip: '清除已完成',
            onPressed: () async {
              await downloadService.clearCompletedRecords();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清除完成记录'), behavior: SnackBarBehavior.floating),
                );
              }
            },
          ),
        ],
      ),
      body: tasksAsync.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('暂无下载任务', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _DownloadTaskTile(
                task: task,
                onCancel: () => downloadService.cancelDownload(task.id),
                onDelete: () => _confirmDelete(context, downloadService, task),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  void _confirmDelete(BuildContext context, DownloadService service, DownloadTask task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除下载'),
        content: Text('确定要删除「${task.vodName} - ${task.episodeName}」吗？本地文件也会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              service.deleteTask(task.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _DownloadTaskTile extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _DownloadTaskTile({
    required this.task,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = DownloadStatus.values[task.status];
    return ListTile(
      leading: _buildStatusIcon(status),
      title: Text(task.vodName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.episodeName, style: const TextStyle(fontSize: 12)),
          if (status == DownloadStatus.downloading)
            LinearProgressIndicator(value: task.progress / 100),
          if (status != DownloadStatus.downloading)
            Text(
              _getStatusText(status, task.progress),
              style: TextStyle(fontSize: 11, color: _getStatusColor(status)),
            ),
        ],
      ),
      trailing: status == DownloadStatus.downloading
          ? IconButton(icon: const Icon(Icons.cancel), onPressed: onCancel)
          : status == DownloadStatus.failed
              ? IconButton(icon: const Icon(Icons.refresh), onPressed: onDelete)
              : IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
    );
  }

  Widget _buildStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.waiting:
        return const Icon(Icons.schedule, color: Colors.grey);
      case DownloadStatus.downloading:
        return const Icon(Icons.downloading, color: Colors.blue);
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  String _getStatusText(DownloadStatus status, int progress) {
    switch (status) {
      case DownloadStatus.waiting:
        return '等待下载';
      case DownloadStatus.downloading:
        return '下载中 $progress%';
      case DownloadStatus.completed:
        return '已完成 · ${_formatFileSize(task.fileSize)}';
      case DownloadStatus.failed:
        return '下载失败';
    }
  }

  Color _getStatusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.waiting:
        return Colors.grey;
      case DownloadStatus.downloading:
        return Colors.blue;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

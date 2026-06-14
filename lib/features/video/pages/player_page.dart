import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放模式枚举
enum PlayMode {
  /// 顺序播放
  sequential,
  /// 单集循环
  loopSingle,
  /// 列表循环
  loopAll,
}

/// 画面比例模式
enum AspectMode {
  /// 原始比例 (BoxFit.contain)
  original,
  /// 16:9
  ratio16_9,
  /// 4:3
  ratio4_3,
  /// 铺满 (BoxFit.fill)
  fill,
  /// 裁剪铺满 (BoxFit.cover)
  cover,
}

class PlayerPage extends ConsumerStatefulWidget {
  final String url;
  final String title;
  final int? episodeIndex;
  final List<String>? episodeNames;
  final List<String>? episodeUrls;

  const PlayerPage({
    super.key,
    required this.url,
    required this.title,
    this.episodeIndex,
    this.episodeNames,
    this.episodeUrls,
  });

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;

  // 控制栏状态
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isLocked = false; // 锁屏模式
  Timer? _hideTimer; // 自动隐藏定时器

  // 播放倍速
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];

  // 播放模式
  PlayMode _playMode = PlayMode.sequential;
  StreamSubscription? _completedSubscription;

  // 画面比例
  AspectMode _aspectMode = AspectMode.original;

  // 手势相关
  double _brightness = 0.5; // 模拟亮度 0~1
  double _volume = 1.0; // 音量 0~1
  bool _showBrightnessIndicator = false;
  bool _showVolumeIndicator = false;
  bool _showProgressIndicator = false; // 滑动进度预览
  Duration _seekPreviewPosition = Duration.zero; // 滑动预览位置
  Duration _dragStartPos = Duration.zero; // 滑动开始时的播放位置
  bool _isHorizontalDrag = false; // 是否已确认为水平滑动
  bool _isVerticalDrag = false; // 是否已确认为垂直滑动
  bool _isDragLeft = false; // 垂直滑动是否在左半屏

  // 播放进度自动保存定时器
  Timer? _progressSaveTimer;

  // 当前播放的集数索引和名称（用于切集时更新）
  int _currentEpisodeIndex = 0;
  String _currentEpisodeName = '';

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: PlayerConfiguration(title: ''));
    _controller = VideoController(_player);
    _player.open(Media(widget.url));
    _player.setRate(_playbackSpeed);
    _currentEpisodeIndex = widget.episodeIndex ?? 0;
    _currentEpisodeName = widget.title;

    // 监听播放完成事件
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (completed) {
        _onPlaybackCompleted();
      }
    });

    // 初始显示控制栏，5秒后自动隐藏
    _startHideTimer();

    // 查询播放进度，提示是否继续播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPlaybackProgress();
    });

    // 每10秒自动保存播放进度
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _savePlaybackProgress();
    });
  }

  @override
  void dispose() {
    // 保存播放进度
    _savePlaybackProgress();
    _progressSaveTimer?.cancel();
    _hideTimer?.cancel();
    _completedSubscription?.cancel();
    _player.dispose();
    // 恢复竖屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ========== 自动隐藏定时器 ==========

  /// 启动5秒自动隐藏定时器
  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  /// 显示控制栏并重启定时器
  void _showControlsAndResetTimer() {
    setState(() => _showControls = true);
    _startHideTimer();
  }

  // ========== 播放进度记忆 ==========

  /// 查询播放进度，提示是否继续播放
  Future<void> _checkPlaybackProgress() async {
    try {
      final db = ref.read(databaseProvider);
      final progress = await db.getPlaybackProgress(widget.url);
      if (progress != null && progress.position > 5000) {
        // 超过5秒，提示是否继续播放
        if (!mounted) return;
        final position = Duration(milliseconds: progress.position);
        final shouldResume = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('继续播放'),
            content: Text('上次播放到 ${_formatDuration(position)}，是否继续播放？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('从头播放'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('继续'),
              ),
            ],
          ),
        );
        if (shouldResume == true && mounted) {
          _player.seek(position);
        }
      }
    } catch (e) {
      // 查询进度失败不影响播放
    }
  }

  /// 保存当前播放进度到数据库
  Future<void> _savePlaybackProgress() async {
    try {
      final position = _player.state.position;
      final duration = _player.state.duration;
      final currentUrl = _currentEpisodeIndex < (widget.episodeUrls?.length ?? 0)
          ? widget.episodeUrls![_currentEpisodeIndex]
          : widget.url;
      final db = ref.read(databaseProvider);
      await db.savePlaybackProgress(PlaybackProgressesCompanion.insert(
        videoUrl: currentUrl,
        position: position.inMilliseconds,
        duration: duration.inMilliseconds,
        lastPlayTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (e) {
      // 保存进度失败不影响播放
    }
  }

  // ========== 播放完成回调 ==========

  void _onPlaybackCompleted() {
    switch (_playMode) {
      case PlayMode.loopSingle:
        // 单集循环：重新播放
        _player.seek(Duration.zero);
        _player.play();
        break;
      case PlayMode.loopAll:
        // 列表循环：有下一集就播下一集，没有就从头播
        if (_hasNextEpisode) {
          _playNextEpisode();
        } else if (widget.episodeUrls != null && widget.episodeUrls!.isNotEmpty) {
          _playEpisodeAtIndex(0);
        } else {
          _player.seek(Duration.zero);
          _player.play();
        }
        break;
      case PlayMode.sequential:
        // 顺序播放：有下一集就播下一集
        if (_hasNextEpisode) {
          _playNextEpisode();
        }
        break;
    }
  }

  // ========== 手势处理 ==========

  /// 单击：显示/隐藏控制栏
  void _onSingleTap() {
    if (_isLocked) {
      // 锁屏状态下单击不做任何操作（解锁由锁图标处理）
      return;
    }
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  /// 双击：播放/暂停
  void _onDoubleTap() {
    if (_isLocked) return;
    if (_player.state.playing) {
      _player.pause();
    } else {
      _player.play();
    }
    _showControlsAndResetTimer();
  }

  /// 手势开始
  void _onPanStart(DragStartDetails details) {
    if (_isLocked) return;
    final dx = details.globalPosition.dx;
    _dragStartPos = _player.state.position;
    _isHorizontalDrag = false;
    _isVerticalDrag = false;
    _isDragLeft = dx < MediaQuery.of(context).size.width / 2;
  }

  /// 手势更新
  void _onPanUpdate(DragUpdateDetails details) {
    if (_isLocked) return;
    final dx = details.delta.dx;
    final dy = details.delta.dy;

    // 判断滑动方向（一旦确认就锁定方向）
    if (!_isHorizontalDrag && !_isVerticalDrag) {
      if (dx.abs() > dy.abs() && dx.abs() > 5) {
        _isHorizontalDrag = true;
      } else if (dy.abs() > dx.abs() && dy.abs() > 5) {
        _isVerticalDrag = true;
      }
    }

    if (_isHorizontalDrag) {
      // 水平滑动：调节进度
      final totalWidth = MediaQuery.of(context).size.width;
      // 每滑动一屏宽度 = 视频总时长
      final duration = _player.state.duration;
      final totalMs = duration.inMilliseconds.toDouble();
      if (totalMs <= 0) return;
      final deltaMs = (dx / totalWidth) * totalMs;
      final newPos = _dragStartPos + Duration(milliseconds: deltaMs.round());
      setState(() {
        _seekPreviewPosition = newPos;
        _showProgressIndicator = true;
      });
    } else if (_isVerticalDrag) {
      if (_isDragLeft) {
        // 左半屏上下滑动：调节亮度
        final totalHeight = MediaQuery.of(context).size.height;
        final delta = -dy / totalHeight; // 向上滑增加亮度
        setState(() {
          _brightness = (_brightness + delta).clamp(0.0, 1.0);
          _showBrightnessIndicator = true;
        });
      } else {
        // 右半屏上下滑动：调节音量
        final totalHeight = MediaQuery.of(context).size.height;
        final delta = -dy / totalHeight; // 向上滑增加音量
        setState(() {
          _volume = (_volume + delta).clamp(0.0, 1.0);
          _showVolumeIndicator = true;
        });
        _player.setVolume(_volume * 100);
      }
      // 隐藏控制栏
      _hideTimer?.cancel();
      setState(() => _showControls = false);
    }
  }

  /// 手势结束
  void _onPanEnd(DragEndDetails details) {
    if (_isLocked) return;
    if (_isHorizontalDrag && _showProgressIndicator) {
      // 松手后跳转到预览位置
      _player.seek(_seekPreviewPosition);
    }
    setState(() {
      _showProgressIndicator = false;
      _showBrightnessIndicator = false;
      _showVolumeIndicator = false;
    });
    _isHorizontalDrag = false;
    _isVerticalDrag = false;
    // 恢复控制栏显示
    _showControlsAndResetTimer();
  }

  // ========== 画面比例 ==========

  /// 获取当前画面比例对应的 BoxFit
  BoxFit _getBoxFit() {
    switch (_aspectMode) {
      case AspectMode.original:
        return BoxFit.contain;
      case AspectMode.fill:
        return BoxFit.fill;
      case AspectMode.cover:
        return BoxFit.cover;
      case AspectMode.ratio16_9:
      case AspectMode.ratio4_3:
        return BoxFit.none; // 通过指定宽高来控制
    }
  }

  /// 获取视频尺寸（16:9/4:3 需要计算）
  (double? width, double? height) _getVideoSize() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    switch (_aspectMode) {
      case AspectMode.ratio16_9:
        final h = screenWidth * 9 / 16;
        return (screenWidth, h > screenHeight ? screenWidth * 16 / 9 : h);
      case AspectMode.ratio4_3:
        final h = screenWidth * 3 / 4;
        return (screenWidth, h > screenHeight ? screenWidth * 4 / 3 : h);
      default:
        // 原始/铺满/裁剪铺满：使用默认尺寸
        if (_isFullscreen) {
          return (screenWidth, screenHeight);
        } else {
          return (screenWidth, screenWidth * 9 / 16);
        }
    }
  }

  /// 显示画面比例选择对话框
  void _showAspectModeSelector() {
    final labels = {
      AspectMode.original: '原始比例',
      AspectMode.ratio16_9: '16:9',
      AspectMode.ratio4_3: '4:3',
      AspectMode.fill: '铺满',
      AspectMode.cover: '裁剪铺满',
    };
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('画面比例'),
        children: AspectMode.values.map((mode) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _aspectMode = mode);
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (_aspectMode == mode)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(labels[mode]!),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ========== 倍速选择 ==========

  void _showSpeedSelector() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('播放速度'),
        children: _speedOptions.map((speed) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _playbackSpeed = speed);
              _player.setRate(speed);
              Navigator.pop(ctx);
              // 倍速切换后 SnackBar 提示
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('播放速度：${speed}x'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (_playbackSpeed == speed)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text('${speed}x'),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ========== 播放模式 ==========

  /// 获取播放模式图标
  IconData _getPlayModeIcon() {
    switch (_playMode) {
      case PlayMode.sequential:
        return Icons.playlist_play;
      case PlayMode.loopSingle:
        return Icons.repeat_one;
      case PlayMode.loopAll:
        return Icons.repeat;
    }
  }

  /// 获取播放模式名称
  String _getPlayModeName() {
    switch (_playMode) {
      case PlayMode.sequential:
        return '顺序播放';
      case PlayMode.loopSingle:
        return '单集循环';
      case PlayMode.loopAll:
        return '列表循环';
    }
  }

  /// 切换播放模式
  void _togglePlayMode() {
    setState(() {
      switch (_playMode) {
        case PlayMode.sequential:
          _playMode = PlayMode.loopSingle;
          break;
        case PlayMode.loopSingle:
          _playMode = PlayMode.loopAll;
          break;
        case PlayMode.loopAll:
          _playMode = PlayMode.sequential;
          break;
      }
    });
    // SnackBar 提示
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_getPlayModeName()),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _showControlsAndResetTimer();
  }

  // ========== 全屏 ==========

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _showControlsAndResetTimer();
  }

  // ========== 画中画/后台播放 ==========

  /// 进入画中画模式（Android 8.0+）
  /// 如果设备不支持 PiP，则退到后台继续播放音频
  void _enterPipMode() async {
    // 先尝试设置 PiP 模式
    try {
      // Android PiP 需要通过原生通道实现
      // 简化方案：退到后台时保持播放
      // 设置为小窗模式
      if (_isFullscreen) {
        _toggleFullscreen();
      }
      // 保存播放状态
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_background_playing', true);
      await prefs.setString('background_play_url', widget.url);
      await prefs.setString('background_play_title', _currentEpisodeName);

      // 退到后台
      // 移动到最近应用
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已进入后台播放模式，音频将继续播放'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // 最小化应用（通过 moveTaskToBack）
      const platform = MethodChannel('com.mediamix.app/background');
      try {
        await platform.invokeMethod('moveToBack');
      } catch (_) {
        // 如果原生通道不可用，仅提示用户手动退到后台
      }
    } catch (e) {
      // PiP 不可用，忽略
    }
  }

  // ========== 切集逻辑 ==========

  bool get _hasPrevEpisode {
    if (widget.episodeUrls == null) return false;
    return _currentEpisodeIndex > 0;
  }

  bool get _hasNextEpisode {
    if (widget.episodeUrls == null) return false;
    return _currentEpisodeIndex < widget.episodeUrls!.length - 1;
  }

  void _playPrevEpisode() {
    if (!_hasPrevEpisode) return;
    _playEpisodeAtIndex(_currentEpisodeIndex - 1);
  }

  void _playNextEpisode() {
    if (!_hasNextEpisode) return;
    _playEpisodeAtIndex(_currentEpisodeIndex + 1);
  }

  void _playEpisodeAtIndex(int index) {
    final newUrl = widget.episodeUrls![index];
    final newName = widget.episodeNames![index];
    // 复用当前播放器，避免页面闪烁
    _player.open(Media(newUrl));
    setState(() {
      _currentEpisodeIndex = index;
      _currentEpisodeName = newName;
    });
    // 保存旧集进度，检查新集进度
    _savePlaybackProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPlaybackProgress();
    });
    _showControlsAndResetTimer();
  }

  // ========== 工具方法 ==========

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ========== 构建 UI ==========

  @override
  Widget build(BuildContext context) {
    final (videoWidth, videoHeight) = _getVideoSize();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 视频画面
          Center(
            child: Video(
              controller: _controller,
              width: videoWidth,
              height: videoHeight,
              fit: _getBoxFit(),
            ),
          ),

          // 手势层（包裹整个视频区域）
          Positioned.fill(
            child: GestureDetector(
              onTap: _onSingleTap,
              onDoubleTap: _onDoubleTap,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),

          // 锁屏状态下只显示中央小锁图标
          if (_isLocked)
            Center(
              child: GestureDetector(
                onTap: () {
                  setState(() => _isLocked = false);
                  _showControlsAndResetTimer();
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Icon(
                    Icons.lock,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),

          // 控制层（非锁屏状态下显示）
          if (_showControls && !_isLocked)
            GestureDetector(
              onTap: () {}, // 拦截点击，防止穿透
              child: Container(
                color: Colors.black26,
                child: SafeArea(
                  child: Column(
                    children: [
                      // 顶部栏
                      _buildTopBar(),
                      const Spacer(),
                      // 进度条
                      _buildProgressBar(),
                      const SizedBox(height: 8),
                      // 底部控制栏
                      _buildBottomControls(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

          // 亮度指示器
          if (_showBrightnessIndicator)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.brightness_medium, color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      '亮度 ${( _brightness * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // 音量指示器
          if (_showVolumeIndicator)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _volume == 0 ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '音量 ${(_volume * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // 滑动进度预览指示器
          if (_showProgressIndicator)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatDuration(_seekPreviewPosition),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建顶部栏
  Widget _buildTopBar() {
    return Row(
      children: [
        // 返回按钮
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        // 标题
        Expanded(
          child: Text(
            _currentEpisodeName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 锁屏按钮
        IconButton(
          icon: Icon(
            _isLocked ? Icons.lock : Icons.lock_open,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() => _isLocked = true);
            _hideTimer?.cancel();
          },
        ),
        // 倍速按钮
        TextButton(
          onPressed: _showSpeedSelector,
          child: Text(
            '${_playbackSpeed}x',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        // 画面比例按钮
        IconButton(
          icon: const Icon(Icons.aspect_ratio, color: Colors.white),
          onPressed: _showAspectModeSelector,
        ),
        // 画中画按钮
        IconButton(
          icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
          onPressed: _enterPipMode,
        ),
        // 全屏按钮
        IconButton(
          icon: Icon(
            _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            color: Colors.white,
          ),
          onPressed: _toggleFullscreen,
        ),
      ],
    );
  }

  /// 构建进度条（含缓冲进度）
  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      initialData: _player.state.position,
      builder: (_, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: _player.stream.duration,
          initialData: _player.state.duration,
          builder: (_, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.toDouble();
            final valueMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs) as double;

            return StreamBuilder<Duration>(
              stream: _player.stream.buffer,
              initialData: _player.state.buffer,
              builder: (_, bufferSnapshot) {
                final buffer = bufferSnapshot.data ?? Duration.zero;
                final bufferMs = buffer.inMilliseconds.toDouble().clamp(0, maxMs);
                final bufferPercent = maxMs > 0 ? bufferMs / maxMs : 0.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 进度条（含缓冲进度叠加）
                      SizedBox(
                        height: 20,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final trackWidth = constraints.maxWidth;
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                // Slider 主体
                                SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                  ),
                                  child: Slider(
                                    value: valueMs,
                                    max: maxMs > 0 ? maxMs : 1,
                                    onChanged: (v) {
                                      _player.seek(Duration(milliseconds: v.toInt()));
                                      _startHideTimer();
                                    },
                                  ),
                                ),
                                // 缓冲进度条（叠加在 Slider 下方）
                                Positioned(
                                  left: 12, // Slider 内边距
                                  right: 12,
                                  top: 0,
                                  bottom: 0,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      height: 3,
                                      width: (trackWidth - 24) * bufferPercent,
                                      decoration: BoxDecoration(
                                        color: Colors.white54,
                                        borderRadius: BorderRadius.circular(1.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      // 时间显示
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// 构建底部控制栏
  Widget _buildBottomControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 播放模式按钮
        IconButton(
          icon: Icon(_getPlayModeIcon(), color: Colors.white, size: 28),
          onPressed: _togglePlayMode,
        ),
        const SizedBox(width: 8),
        // 上一集
        if (_hasPrevEpisode)
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.white, size: 32),
            onPressed: _playPrevEpisode,
          ),
        const SizedBox(width: 8),
        // 后退10秒
        IconButton(
          icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
          onPressed: () {
            final pos = _player.state.position;
            _player.seek(pos - const Duration(seconds: 10));
            _showControlsAndResetTimer();
          },
        ),
        const SizedBox(width: 8),
        // 播放/暂停
        StreamBuilder<bool>(
          stream: _player.stream.playing,
          initialData: _player.state.playing,
          builder: (_, snapshot) {
            final playing = snapshot.data ?? false;
            return IconButton(
              icon: Icon(
                playing ? Icons.pause_circle : Icons.play_circle,
                color: Colors.white,
                size: 56,
              ),
              onPressed: () {
                if (playing) {
                  _player.pause();
                } else {
                  _player.play();
                }
                _showControlsAndResetTimer();
              },
            );
          },
        ),
        const SizedBox(width: 8),
        // 前进10秒
        IconButton(
          icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
          onPressed: () {
            final pos = _player.state.position;
            _player.seek(pos + const Duration(seconds: 10));
            _showControlsAndResetTimer();
          },
        ),
        const SizedBox(width: 8),
        // 下一集
        if (_hasNextEpisode)
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white, size: 32),
            onPressed: _playNextEpisode,
          ),
      ],
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// 与自定义 SubtitleTrack 冲突，使用自定义版本
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/services/power_manager_service.dart';
import '../providers/video_providers.dart';
import '../models/video_models.dart' show VideoParser;
import '../core/player_core_manager.dart';
import '../services/subtitle_service.dart';

const _kHideControlsDelay = Duration(seconds: 5);
const _kSpeedIndicatorDuration = Duration(seconds: 3);

class PlayerPage extends ConsumerStatefulWidget {
  final String url;
  final String title;
  final int? episodeIndex;
  final List<String>? episodeNames;
  final List<String>? episodeUrls;
  final List<String>? qualityLabels;
  final List<String>? qualityUrls;
  final List<String>? subtitleUrls;

  const PlayerPage({
    super.key,
    required this.url,
    required this.title,
    this.episodeIndex,
    this.episodeNames,
    this.episodeUrls,
    this.qualityLabels,
    this.qualityUrls,
    this.subtitleUrls,
  });

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> with WidgetsBindingObserver {
  late final PlayerCoreManager _manager;

  // UI-only 状态
  bool _showControls = true;
  bool _isLocked = false;
  bool _isFullscreen = false;
  Timer? _hideTimer;

  // 手势状态
  bool _isHorizontalDrag = false;
  bool _isVerticalDrag = false;
  bool _isDragLeft = false;
  Duration _seekPreviewPosition = Duration.zero;
  Duration _dragStartPos = Duration.zero;
  bool _showBrightnessIndicator = false;
  bool _showVolumeIndicator = false;
  bool _showProgressIndicator = false;

  // 倍速指示器计时
  Timer? _speedIndicatorTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 立即全屏 + 暗色状态栏，消除进入时的灰色闪现
    _enterFullscreen();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      systemNavigationBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    _manager = PlayerCoreManager();

    // 注册 UI 通知回调
    _manager.onFirstFrame = _onFirstFrame;
    _manager.onError = _onError;
    _manager.onQualitySuggestion = _onQualitySuggestion;
    _manager.onProgressResume = _onProgressResume;
    _manager.onQualityAutoSwitch = _onQualityAutoSwitch;
    _manager.onSubtitlesLoaded = _onSubtitlesLoaded;
    _manager.onNotifyPreloadBuffering = _onNotifyPreloadBuffering;

    // Phase 1: 同步创建 Player + VideoController（让 Video 组件立即可用）
    _manager.initPlayerSync();

    // Phase 2: 延后到首帧之后再执行耗时初始化
    final db = ref.read(databaseProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _manager.initialize(
        url: widget.url,
        title: widget.title,
        episodeIndex: widget.episodeIndex,
        episodeNames: widget.episodeNames,
        episodeUrls: widget.episodeUrls,
        qualityLabels: widget.qualityLabels,
        qualityUrls: widget.qualityUrls,
        subtitleUrls: widget.subtitleUrls,
        db: db,
      ).then((_) {
        if (mounted) {
          _checkAndResumeProgress();
          _manager.preloadAdjacentEpisodes();
        }
      }).catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('播放器初始化失败: $e'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    });

    // 初始显示控制栏，5秒后自动隐藏
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _speedIndicatorTimer?.cancel();
    _manager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _exitFullscreen();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _manager.onAppLifecycleStateChanged(state);
  }

  // ========================================================================
  // PlayerCoreManager 回调 — 纯 UI 反应
  // ========================================================================

  void _onFirstFrame(FirstFrameEvent event) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('首帧耗时: ${event.firstFrameTimeMs}ms'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onError(ErrorEvent event) {
    if (!mounted) return;
    _showErrorDialog(event);
  }

  void _onQualitySuggestion(QualitySuggestionEvent event) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('网络质量: ${event.networkQualityDescription}，建议画质: ${event.qualityLabel}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onProgressResume(ProgressResumeEvent event) {
    if (!mounted) return;
    _showResumeDialog(event.position);
  }

  void _onQualityAutoSwitch(QualityAutoSwitchEvent event) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('自动切换清晰度: ${event.label}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onSubtitlesLoaded(List<SubtitleTrack> tracks) {
    if (mounted) setState(() {});
  }

  void _onNotifyPreloadBuffering(bool isBuffering) {
    try {
      final preloadService = ref.read(preloadServiceProvider);
      preloadService.notifyPlaybackBuffering(isBuffering);
    } catch (e) {
      debugPrint('预加载服务通知失败: $e');
    }
  }

  // ========================================================================
  // 进度恢复
  // ========================================================================

  Future<void> _checkAndResumeProgress() async {
    final position = await _manager.checkPlaybackProgress();
    if (position != null && mounted) {
      _showResumeDialog(position);
    }
  }

  void _showResumeDialog(Duration position) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('继续播放'),
        content: Text('上次播放到 ${_manager.formatDuration(position)}，是否继续播放？'),
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
    ).then((shouldResume) {
      if (shouldResume == true) {
        _manager.resumeToPosition(position);
      }
    });
  }

  // ========================================================================
  // 错误对话框
  // ========================================================================

  void _showErrorDialog(ErrorEvent event) {
    final triedInfo = event.triedQualityCount > 0
        ? '\n已尝试${event.triedQualityCount + 1}个清晰度，均失败'
        : '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('播放错误'),
        content: Text(
          '播放遇到问题$triedInfo：${event.message.length > 100 ? '${event.message.substring(0, 100)}...' : event.message}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('退出'),
          ),
          if (event.hasNextEpisode)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _manager.playNextEpisode();
              },
              child: const Text('下一集'),
            ),
          if (event.hasUntriedQuality && event.untriedQualityLabel != null)
            TextButton(
              onPressed: () {
                final next = _manager.findNextUntriedQuality();
                Navigator.pop(ctx);
                _manager.resetRetryCount();
                _manager.switchQuality(next);
              },
              child: Text('切换${event.untriedQualityLabel}'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _manager.retryPlayback();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // 自动隐藏定时器
  // ========================================================================

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_kHideControlsDelay, () {
      if (mounted && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsAndResetTimer() {
    setState(() => _showControls = true);
    _startHideTimer();
  }

  // ========================================================================
  // 手势处理
  // ========================================================================

  void _onSingleTap() {
    if (_isLocked) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (_isLocked) return;
    final width = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;
    if (dx < width * 0.3) {
      final pos = _manager.player.state.position;
      _manager.fastSeek(pos - Duration(seconds: _manager.skipInterval));
    } else if (dx > width * 0.7) {
      final pos = _manager.player.state.position;
      _manager.fastSeek(pos + Duration(seconds: _manager.skipInterval));
    } else {
      _manager.togglePlayPause();
    }
    _showControlsAndResetTimer();
  }

  void _onPanStart(DragStartDetails details) {
    if (_isLocked) return;
    _dragStartPos = _manager.player.state.position;
    _isHorizontalDrag = false;
    _isVerticalDrag = false;
    _isDragLeft = details.globalPosition.dx < MediaQuery.of(context).size.width / 2;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isLocked) return;
    final dx = details.delta.dx;
    final dy = details.delta.dy;

    if (!_isHorizontalDrag && !_isVerticalDrag) {
      if (dx.abs() > dy.abs() && dx.abs() > 5) {
        _isHorizontalDrag = true;
      } else if (dy.abs() > dx.abs() && dy.abs() > 5) {
        _isVerticalDrag = true;
      }
    }

    if (_isHorizontalDrag) {
      final totalWidth = MediaQuery.of(context).size.width;
      final duration = _manager.player.state.duration;
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
        final totalHeight = MediaQuery.of(context).size.height;
        final delta = -dy / totalHeight;
        final newBrightness = (_manager.brightness + delta).clamp(0.0, 1.0);
        _manager.setBrightness(newBrightness);
        setState(() => _showBrightnessIndicator = true);
      } else {
        final totalHeight = MediaQuery.of(context).size.height;
        final delta = -dy / totalHeight;
        final newVolume = (_manager.volume + delta).clamp(0.0, 1.0);
        _manager.setVolume(newVolume);
        setState(() => _showVolumeIndicator = true);
      }
      _hideTimer?.cancel();
      setState(() => _showControls = false);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isLocked) return;
    if (_isHorizontalDrag && _showProgressIndicator) {
      _manager.fastSeek(_seekPreviewPosition);
    }
    setState(() {
      _showProgressIndicator = false;
      _showBrightnessIndicator = false;
      _showVolumeIndicator = false;
    });
    _isHorizontalDrag = false;
    _isVerticalDrag = false;
    _showControlsAndResetTimer();
  }

  // ========================================================================
  // 画面比例辅助
  // ========================================================================

  BoxFit _getBoxFit() {
    switch (_manager.aspectMode) {
      case AspectMode.original:
        return BoxFit.contain;
      case AspectMode.fill:
        return BoxFit.fill;
      case AspectMode.cover:
        return BoxFit.cover;
      case AspectMode.ratio16_9:
      case AspectMode.ratio4_3:
        return BoxFit.none;
    }
  }

  (double? width, double? height) _getVideoSize() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    switch (_manager.aspectMode) {
      case AspectMode.ratio16_9:
        final h = screenWidth * 9 / 16;
        return (screenWidth, h > screenHeight ? screenWidth * 16 / 9 : h);
      case AspectMode.ratio4_3:
        final h = screenWidth * 3 / 4;
        return (screenWidth, h > screenHeight ? screenWidth * 4 / 3 : h);
      default:
        if (_isFullscreen) {
          return (screenWidth, screenHeight);
        } else {
          return (screenWidth, screenWidth * 9 / 16);
        }
    }
  }

  // ========================================================================
  // UI 映射辅助 — 纯 UI 类型映射
  // ========================================================================

  IconData _getPowerModeIcon(PowerMode mode) {
    switch (mode) {
      case PowerMode.fullPerformance:
        return Icons.speed;
      case PowerMode.balanced:
        return Icons.balance;
      case PowerMode.powerSaving:
        return Icons.battery_saver;
    }
  }

  IconData _getPlayModeIcon() {
    switch (_manager.playMode) {
      case PlayMode.sequential:
        return Icons.playlist_play;
      case PlayMode.loopSingle:
        return Icons.repeat_one;
      case PlayMode.loopAll:
        return Icons.repeat;
    }
  }

  String _getPlayModeName() {
    switch (_manager.playMode) {
      case PlayMode.sequential:
        return '顺序播放';
      case PlayMode.loopSingle:
        return '单集循环';
      case PlayMode.loopAll:
        return '列表循环';
    }
  }

  // ========================================================================
  // 选择器对话框
  // ========================================================================

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
              _manager.setAspectMode(mode);
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (_manager.aspectMode == mode)
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

  void _showSpeedSelector() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('播放速度'),
        children: _manager.speedOptions.map((speed) {
          return SimpleDialogOption(
            onPressed: () {
              _manager.setPlaybackSpeed(speed);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('播放速度：${speed}x'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              _showControlsAndResetTimer();
              // 倍速指示器
              _speedIndicatorTimer?.cancel();
              _speedIndicatorTimer = Timer(_kSpeedIndicatorDuration, () {
                if (mounted) setState(() {});
              });
            },
            child: Row(
              children: [
                if (_manager.playbackSpeed == speed)
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

  void _showSkipIntervalSelector() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('快进/后退间隔'),
        children: _manager.skipIntervals.map((interval) {
          return SimpleDialogOption(
            onPressed: () {
              _manager.setSkipInterval(interval);
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (_manager.skipInterval == interval)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text('$interval秒'),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showQualitySelector() {
    final labels = _manager.qualityLabels;
    if (labels.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('清晰度'),
        children: List.generate(labels.length, (i) {
          return SimpleDialogOption(
            onPressed: () {
              if (i != _manager.currentQualityIndex) {
                _manager.clearTriedQualityIndices();
                _manager.switchQuality(i);
              }
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (_manager.currentQualityIndex == i)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(labels[i]),
              ],
            ),
          );
        }),
      ),
    );
  }

  void _showSubtitleTrackSelector() {
    final tracks = _manager.subtitleTracks;
    if (tracks.length <= 1) {
      _manager.toggleSubtitles();
      _showControlsAndResetTimer();
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('字幕'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              _manager.hideSubtitles();
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (!_manager.showSubtitles)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('关闭'),
              ],
            ),
          ),
          ...List.generate(tracks.length, (i) {
            return SimpleDialogOption(
              onPressed: () {
                _manager.setSubtitleTrack(i);
                Navigator.pop(ctx);
                _showControlsAndResetTimer();
              },
              child: Row(
                children: [
                  if (_manager.showSubtitles && _manager.currentSubtitleTrack == i)
                    const Icon(Icons.check, size: 18)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Text(tracks[i].label),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showPowerModeSelector() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('功耗模式'),
        children: PowerMode.values.map((mode) {
          return SimpleDialogOption(
            onPressed: () {
              _manager.setPowerMode(mode);
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (_manager.powerMode == mode)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Icon(_getPowerModeIcon(mode), size: 18),
                const SizedBox(width: 8),
                Text(_manager.getPowerModeName(mode)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ========================================================================
  // 播放模式切换
  // ========================================================================

  void _togglePlayMode() {
    final next = switch (_manager.playMode) {
      PlayMode.sequential => PlayMode.loopSingle,
      PlayMode.loopSingle => PlayMode.loopAll,
      PlayMode.loopAll => PlayMode.sequential,
    };
    _manager.setPlayMode(next);
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

  // ========================================================================
  // 全屏切换
  // ========================================================================

  void _enterFullscreen() {
    _isFullscreen = true;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullscreen() {
    _isFullscreen = false;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _toggleFullscreen() {
    if (_isFullscreen) {
      _exitFullscreen();
    } else {
      _enterFullscreen();
    }
    _showControlsAndResetTimer();
  }

  // ========================================================================
  // 解析器选择
  // ========================================================================

  void _showParserSelector() {
    final parsers = VideoParser.defaultParsers;
    final current = _manager.activeParser;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择解析接口'),
        children: [
          // 直连选项
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _manager.setParser(null);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                Icon(
                  current == null ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18,
                  color: current == null ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                const Text('直连（不使用解析）'),
              ],
            ),
          ),
          ...parsers.map((p) => SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _manager.setParser(p);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                Icon(
                  current?.key == p.key ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18,
                  color: current?.key == p.key ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                Text(p.urlTemplate.substring(0, p.urlTemplate.indexOf('?')).replaceAll('https://', '').replaceAll('http://', ''), style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildParserButton() {
    final current = _manager.activeParser;
    return GestureDetector(
      onTap: _showParserSelector,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: current != null ? Colors.orange : Colors.white24, width: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          current?.name ?? '直连',
          style: TextStyle(color: current != null ? Colors.orange : Colors.white70, fontSize: 11),
        ),
      ),
    );
  }

  // ========================================================================
  // 画中画
  // ========================================================================

  void _enterPipMode() async {
    if (_isFullscreen) {
      _toggleFullscreen();
    }
    _manager.enterPipMode();
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已进入后台播放模式，音频将继续播放'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ========================================================================
  // 构建 UI
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    final (videoWidth, videoHeight) = _getVideoSize();

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _manager,
        builder: (context, _) {
          return Stack(
            children: [
              // 视频画面
              Center(
                child: Video(
                  controller: _manager.controller,
                  width: videoWidth,
                  height: videoHeight,
                  fit: _getBoxFit(),
                ),
              ),

              // 手势层
              Positioned.fill(
                child: GestureDetector(
                  onTap: _onSingleTap,
                  onDoubleTapDown: _onDoubleTapDown,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),

              // 字幕叠加层
              if (_manager.showSubtitles && _manager.subtitleTracks.isNotEmpty)
                SubtitleOverlay(
                  text: null,
                  tracks: _manager.subtitleTracks,
                  currentTrackIndex: _manager.currentSubtitleTrack,
                  position: _manager.lastVideoPosition,
                  subtitleService: _manager.subtitleService,
                ),

              // 加载/缓冲覆盖层
              if (_manager.isLoading)
                _buildLoadingOverlay(),

              // Seek进度覆盖层
              if (_manager.isSeeking)
                _buildSeekingOverlay(),

              // 倍速指示器覆盖层
              if (_manager.playbackSpeed != 1.0 && _speedIndicatorTimer?.isActive == true)
                _buildSpeedIndicator(),

              // 锁屏状态下只显示中央小锁图标
              if (_isLocked)
                _buildLockIcon(),

              // 控制层（非锁屏状态下显示）
              if (_showControls && !_isLocked)
                _buildControlsLayer(),

              // 亮度指示器
              if (_showBrightnessIndicator)
                _buildBrightnessIndicator(),

              // 音量指示器
              if (_showVolumeIndicator)
                _buildVolumeIndicator(),

              // 滑动进度预览指示器
              if (_showProgressIndicator)
                _buildProgressIndicator(),
            ],
          );
        },
      ),
    );
  }

  // ========================================================================
  // Widget 构建器
  // ========================================================================

  Widget _buildLoadingOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _manager.loadingText,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (_manager.bufferPercent > 0) ...[
              const SizedBox(height: 8),
              Text(
                '缓冲: ${(_manager.bufferPercent * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
            if (_manager.networkSpeedText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '网速: ${_manager.networkSpeedText}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeekingOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 12),
            Text(
              '跳转中...',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedIndicator() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${_manager.playbackSpeed}x',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildLockIcon() {
    return Center(
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
    );
  }

  Widget _buildControlsLayer() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        color: Colors.black26,
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              const Spacer(),
              _buildProgressBar(),
              const SizedBox(height: 8),
              _buildBottomControls(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // 返回
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: () {
              _exitFullscreen();
              Navigator.pop(context);
            },
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          // 标题
          Expanded(
            child: Text(
              _manager.currentEpisodeName,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 倍速
          _buildCompactButton(
            onTap: _showSpeedSelector,
            child: Text('${_manager.playbackSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          // 清晰度
          if (_manager.hasQualityOptions)
            _buildCompactButton(
              onTap: _showQualitySelector,
              child: Text(_manager.qualityLabels[_manager.currentQualityIndex], style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          // 字幕
          _buildCompactIcon(
            icon: _manager.showSubtitles ? Icons.closed_caption : Icons.closed_caption_disabled,
            enabled: _manager.subtitleTracks.isNotEmpty,
            onTap: _manager.subtitleTracks.isNotEmpty ? _showSubtitleTrackSelector : null,
          ),
          // 解析器
          _buildParserButton(),
          // 更多
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
            color: const Color(0xFF2A2A2A),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onSelected: (v) {
              switch (v) {
                case 'aspect': _showAspectModeSelector();
                case 'power': _showPowerModeSelector();
                case 'pip': _enterPipMode();
                case 'playmode': _togglePlayMode();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'playmode',
                child: Row(children: [Icon(_getPlayModeIcon(), size: 20, color: Colors.white70), const SizedBox(width: 12), const Text('播放模式')]),
              ),
              PopupMenuItem(
                value: 'aspect',
                child: const Row(children: [Icon(Icons.aspect_ratio, size: 20, color: Colors.white70), SizedBox(width: 12), Text('画面比例')]),
              ),
              PopupMenuItem(
                value: 'power',
                child: Row(children: [Icon(_getPowerModeIcon(_manager.powerMode), size: 20, color: Colors.white70), const SizedBox(width: 12), const Text('功耗模式')]),
              ),
              PopupMenuItem(
                value: 'pip',
                child: const Row(children: [Icon(Icons.picture_in_picture_alt, size: 20, color: Colors.white70), SizedBox(width: 12), Text('后台播放')]),
              ),
            ],
          ),
          // 锁屏
          _buildCompactIcon(
            icon: _isLocked ? Icons.lock : Icons.lock_open,
            enabled: true,
            onTap: () {
              setState(() => _isLocked = true);
              _hideTimer?.cancel();
            },
          ),
          // 全屏
          _buildCompactIcon(
            icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            enabled: true,
            onTap: _toggleFullscreen,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactButton({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: child,
      ),
    );
  }

  Widget _buildCompactIcon({required IconData icon, required bool enabled, VoidCallback? onTap}) {
    return IconButton(
      icon: Icon(icon, color: enabled ? Colors.white : Colors.white30, size: 20),
      onPressed: onTap,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: _manager.player.stream.position,
      initialData: _manager.player.state.position,
      builder: (_, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: _manager.player.stream.duration,
          initialData: _manager.player.state.duration,
          builder: (_, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.toDouble();
            final valueMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);

            return StreamBuilder<Duration>(
              stream: _manager.player.stream.buffer,
              initialData: _manager.player.state.buffer,
              builder: (_, bufferSnapshot) {
                final buffer = bufferSnapshot.data ?? Duration.zero;
                final bufferMs = buffer.inMilliseconds.toDouble().clamp(0, maxMs);
                final bufferPercent = maxMs > 0 ? bufferMs / maxMs : 0.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 20,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final trackWidth = constraints.maxWidth;
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                SliderTheme(
                                  data: const SliderThemeData(
                                    trackHeight: 3,
                                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                                    overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                  ),
                                  child: Slider(
                                    value: valueMs,
                                    max: maxMs > 0 ? maxMs : 1,
                                    onChanged: (v) {
                                      _manager.fastSeek(Duration(milliseconds: v.toInt()));
                                      _startHideTimer();
                                    },
                                  ),
                                ),
                                Positioned(
                                  left: 12,
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _manager.formatDuration(position),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          Text(
                            _manager.formatDuration(duration),
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
        if (_manager.hasPrevEpisode)
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.white, size: 32),
            onPressed: _manager.playPrevEpisode,
          ),
        const SizedBox(width: 8),
        // 后退N秒
        GestureDetector(
          onLongPress: () {
            _showControlsAndResetTimer();
            _showSkipIntervalSelector();
          },
          child: IconButton(
            icon: const Icon(Icons.replay, color: Colors.white, size: 32),
            onPressed: () {
              final pos = _manager.player.state.position;
              _manager.fastSeek(pos - Duration(seconds: _manager.skipInterval));
              _showControlsAndResetTimer();
            },
          ),
        ),
        const SizedBox(width: 8),
        // 播放/暂停
        StreamBuilder<bool>(
          stream: _manager.player.stream.playing,
          initialData: _manager.player.state.playing,
          builder: (_, snapshot) {
            final playing = snapshot.data ?? false;
            return IconButton(
              icon: Icon(
                playing ? Icons.pause_circle : Icons.play_circle,
                color: Colors.white,
                size: 56,
              ),
              onPressed: () {
                _manager.togglePlayPause();
                _showControlsAndResetTimer();
              },
            );
          },
        ),
        const SizedBox(width: 8),
        // 前进N秒
        GestureDetector(
          onLongPress: () {
            _showControlsAndResetTimer();
            _showSkipIntervalSelector();
          },
          child: IconButton(
            icon: const Icon(Icons.forward_30, color: Colors.white, size: 32),
            onPressed: () {
              final pos = _manager.player.state.position;
              _manager.fastSeek(pos + Duration(seconds: _manager.skipInterval));
              _showControlsAndResetTimer();
            },
          ),
        ),
        const SizedBox(width: 8),
        // 下一集
        if (_manager.hasNextEpisode)
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white, size: 32),
            onPressed: _manager.playNextEpisode,
          ),
      ],
    );
  }

  Widget _buildBrightnessIndicator() {
    return Center(
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
              '亮度 ${(_manager.brightness * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeIndicator() {
    return Center(
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
              _manager.volume == 0 ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              '音量 ${(_manager.volume * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _manager.formatDuration(_seekPreviewPosition),
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

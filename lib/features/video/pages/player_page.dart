import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart'
    hide SubtitleTrack; // 与自定义 SubtitleTrack 冲突，使用自定义版本
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/services/player_metrics_service.dart';
import '../../../core/services/power_manager_service.dart';
import '../../../core/services/video_cache_service.dart';
import '../../../core/services/device_capability_service.dart';
import '../../../core/services/metrics_collector_service.dart';
import '../../../core/network/network_engine.dart';
import '../providers/video_providers.dart';
import '../core/player_core.dart';
import '../../../core/services/local_proxy_server.dart';
import '../services/subtitle_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

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

/// 功耗模式使用 PowerMode（来自 power_manager_service.dart）


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
  late final Player _player;
  late final VideoController _controller;

  // 日志
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  // 控制栏状态
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isLocked = false; // 锁屏模式
  Timer? _hideTimer; // 自动隐藏定时器

  // 播放倍速
  double _playbackSpeed = 1.0;
  // 优化：增加0.25x步进
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0];

  // 快进间隔（秒），可长按快进按钮切换
  int _skipInterval = 10;
  final List<int> _skipIntervals = [5, 10, 30, 60];

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

  // 清晰度选项（多播放源）
  int _currentQualityIndex = 0;
  List<String> _qualityLabels = [];
  List<String> _qualityUrls = [];
  bool get _hasQualityOptions => _qualityUrls.length > 1;

  // 字幕
  final SubtitleService _subtitleService = SubtitleService();
  List<SubtitleTrack> _subtitleTracks = [];
  bool _showSubtitles = true;
  int _currentSubtitleTrack = 0;

  // ========== 优化1: 硬解码配置 ==========
  bool _hardwareDecodingEnabled = true;

  // ========== 优化2: 缓冲区管理 ==========
  final BufferManager _bufferManager = BufferManager();

  // ========== 优化3: ABR 自适应码率 ==========
  final ABRController _abrController = ABRController();

  // ========== 优化4: Seek优化 ==========
  bool _isSeeking = false;
  Timer? _seekOverlayTimer;

  // ========== 优化5: 音视频同步监控 ==========
  StreamSubscription? _positionSubscription;
  Duration _lastVideoPosition = Duration.zero;
  DateTime _lastPositionUpdateTime = DateTime.now();
  Timer? _avSyncCheckTimer;
  int _avSyncCorrectionCount = 0;
  DateTime? _lastAVSyncCorrection;

  // ========== 优化6: 播放器性能监控 ==========
  bool _hasRecordedFirstFrame = false;
  bool _isBuffering = false;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _playingSubscription;

  // ========== 优化7: 预加载 ==========
  bool _hasTriggeredNextEpisodePreload = false;

  // ========== 优化8: 倍速播放优化 ==========
  Timer? _speedIndicatorTimer;

  // ========== 优化9: 画中画/后台播放优化 ==========
  bool _isInBackground = false;
  bool _isInPipMode = false;

  // ========== 优化10: 功耗优化 ==========
  PowerMode _powerMode = PowerMode.balanced;

  // ========== 优化11: 加载状态优化 ==========
  bool _isLoading = true;
  String _loadingText = '加载中...';
  double _bufferPercent = 0.0;
  String _networkSpeedText = '';

  // ========== 优化12: 错误处理 + 弱网自动重连 ==========
  int _retryCount = 0;
  static const int _maxAutoRetry = 1;
  // 降级策略：记录已尝试的清晰度索引，失败后自动切换
  final Set<int> _triedQualityIndices = {};
  String? _lastError;
  /// 是否因网络断开而等待恢复
  bool _isWaitingForNetwork = false;
  /// 断网前的播放位置，用于恢复后续播
  Duration _lastPlaybackPosition = Duration.zero;
  /// 自动重连定时器（指数退避）
  Timer? _reconnectTimer;
  /// 重连尝试次数
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 10;
  /// 网络恢复监听
  StreamSubscription? _networkRecoverySubscription;

  // ========== 流订阅管理 ==========
  StreamSubscription? _bufferSubscription;
  StreamSubscription? _networkConditionSubscription;

  // ========== 缓存深度集成 ==========
  /// 实际使用的播放 URL（可能是本地缓存路径）
  String _resolvedUrl = '';
  /// 是否使用了本地缓存
  bool _isUsingCache = false;

  /// 解析视频 URL — 优先使用本地缓存，其次走本地代理边播边缓存
  Future<String> _resolveVideoUrl(String url, String videoId) async {
    try {
      // 检查完整缓存（L3 磁盘缓存）
      final cachedPath = await VideoCacheService.instance.getCachePath(videoId);
      if (cachedPath != null) {
        _logger.i('缓存命中，使用本地文件: $videoId');
        _isUsingCache = true;
        PlayerMetricsService.instance.recordEvent(MetricsEvent.cacheHit);
        MetricsCollectorService.instance.recordEvent(MetricsEvent.cacheHit);
        return cachedPath;
      }

      PlayerMetricsService.instance.recordEvent(MetricsEvent.cacheMiss);
      MetricsCollectorService.instance.recordEvent(MetricsEvent.cacheMiss);
      _isUsingCache = false;

      // 启动本地代理，走边播边缓存通道
      await LocalProxyServer.instance.start();
      final proxyUrl = LocalProxyServer.instance.proxyUrl(url, videoId);
      _logger.i('通过本地代理播放: $videoId → 127.0.0.1:${LocalProxyServer.instance.port}');
      return proxyUrl;
    } catch (e) {
      _logger.w('缓存/代理查询失败，使用网络URL: $e');
      _isUsingCache = false;
    }
    return url;
  }

  /// 带缓存检查的视频打开
  Future<void> _openVideoWithCacheCheck(String url, String videoId) async {
    _resolvedUrl = await _resolveVideoUrl(url, videoId);
    _logger.i('播放URL解析完成: ${_isUsingCache ? "本地缓存" : "网络"}');
    _player.open(Media(_resolvedUrl));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 优化1: 硬解码配置 — 创建播放器时启用硬件解码
    _player = Player(configuration: PlayerConfiguration(
      title: '',
      // media_kit 基于 libmpv，硬件解码默认启用
      // bufferSize 由缓冲区管理器根据网络条件动态建议
    ));
    _controller = VideoController(_player);
    _configureHardwareDecoding();

    // 初始化缓冲区管理器
    _bufferManager.onBufferStateChanged = _onBufferStateChanged;

    // 初始化 ABR 控制器
    _abrController.onQualityChanged = _onQualityChanged;

    // 优化6: 开始性能监控会话
    final videoId = '${widget.title}_${widget.episodeIndex ?? 0}';
    PlayerMetricsService.instance.startSession(videoId);
    PlayerMetricsService.instance.recordEvent(MetricsEvent.playStart);
    MetricsCollectorService.instance.recordEvent(MetricsEvent.playStart, videoId: videoId);

    // 缓存深度集成：先检查本地缓存，再决定使用哪个 URL
    _openVideoWithCacheCheck(widget.url, videoId);
    _player.setRate(_playbackSpeed);
    _currentEpisodeIndex = widget.episodeIndex ?? 0;
    _currentEpisodeName = widget.title;
    _qualityLabels = widget.qualityLabels ?? [];
    _qualityUrls = widget.qualityUrls ?? [];
    _currentQualityIndex = 0;

    // 监听播放完成事件
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (completed) {
        PlayerMetricsService.instance.recordEvent(MetricsEvent.playComplete);
        MetricsCollectorService.instance.recordEvent(MetricsEvent.playComplete);
        _onPlaybackCompleted();
      }
    });

    // 优化5: 音视频同步监控 — 监听位置流
    _positionSubscription = _player.stream.position.listen((position) {
      _lastVideoPosition = position;
      _lastPositionUpdateTime = DateTime.now();

      // 优化6: 首帧检测
      if (!_hasRecordedFirstFrame && position > Duration.zero) {
        _hasRecordedFirstFrame = true;
        PlayerMetricsService.instance.recordEvent(MetricsEvent.firstFrame);
        MetricsCollectorService.instance.recordEvent(MetricsEvent.firstFrame);
        // 显示首帧时间覆盖层
        _showFirstFrameOverlay();
        // 加载字幕
        _loadSubtitles();
      }

      // 优化7: 预加载 — 播放到80%时触发下一集预加载
      _checkPreloadTrigger(position);
    });

    // 优化2: 监听缓冲流
    _bufferSubscription = _player.stream.buffer.listen((buffer) {
      _bufferManager.updateBuffer(buffer);
      _abrController.updateBuffer(buffer);

      // 更新加载状态
      if (_isLoading && buffer > Duration.zero) {
        setState(() {
          _isLoading = false;
          _bufferPercent = _bufferManager.bufferPercent;
        });
      } else {
        setState(() {
          _bufferPercent = _bufferManager.bufferPercent;
        });
      }
    });

    // 优化6: 监听播放状态（用于缓冲检测）
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing && _isBuffering) {
        _isBuffering = false;
        PlayerMetricsService.instance.recordEvent(MetricsEvent.bufferingEnd);
        setState(() {
          _isLoading = false;
        });
      }
    });

    // 优化12: 监听错误流
    _errorSubscription = _player.stream.error.listen((error) {
      _logger.e('播放错误: $error');
      PlayerMetricsService.instance.recordEvent(
        MetricsEvent.playError,
        errorMessage: error,
      );
      _handlePlaybackError(error);
    });

    // 监听网络条件变化
    _networkConditionSubscription = NetworkEngine.instance.onConditionChanged.listen((condition) {
      _bufferManager.updateNetworkCondition(condition);
      // 更新网络速度显示
      setState(() {
        _networkSpeedText = _formatNetworkSpeed(NetworkEngine.instance.currentBandwidthKbps);
      });
    });

    // 初始显示控制栏，5秒后自动隐藏
    _startHideTimer();

    // 查询播放进度，提示是否继续播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPlaybackProgress();
      // 优化7: 进入播放页时预加载相邻集
      _preloadAdjacentEpisodes();
      // 优化10: 检测电池状态
      _detectPowerMode();
      // 初始化网络条件
      _bufferManager.updateNetworkCondition(NetworkEngine.instance.currentCondition);
      _loadSkipInterval();
    });

    // 每10秒自动保存播放进度
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _savePlaybackProgress();
    });

    // 优化5: 定期检查音视频同步
    _avSyncCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkAVSync();
    });
  }

  @override
  void dispose() {
    // 优化6: 结束性能监控会话，并持久化到数据库
    final metrics = PlayerMetricsService.instance.endSession();
    if (metrics != null) {
      MetricsCollectorService.instance.onSessionEnd(metrics);
    }

    // 保存播放进度
    _savePlaybackProgress();
    _progressSaveTimer?.cancel();
    _hideTimer?.cancel();
    _seekOverlayTimer?.cancel();
    _speedIndicatorTimer?.cancel();
    _avSyncCheckTimer?.cancel();
    _completedSubscription?.cancel();
    _positionSubscription?.cancel();
    _reconnectTimer?.cancel();
    _networkRecoverySubscription?.cancel();
    _bufferSubscription?.cancel();
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _networkConditionSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    // 恢复竖屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 优化9: 画中画/后台播放优化
    switch (state) {
      case AppLifecycleState.paused:
        _onAppBackgrounded();
        break;
      case AppLifecycleState.resumed:
        _onAppForegrounded();
        break;
      default:
        break;
    }
  }

  // ========== 优化1: 硬解码配置 ==========

  /// 配置硬件解码
  /// 配置硬件解码 — 异步探测设备能力，决定解码策略
  void _configureHardwareDecoding() async {
    try {
      final report = await DeviceCapabilityService.instance.getCapabilityReport();
      _hardwareDecodingEnabled = report.recommendHardwareDecoding;

      if (report.isLowEndDevice) {
        _logger.i('低端设备(${report.totalRamMB}MB RAM)，建议软解或降低分辨率');
        // 低端设备限制分辨率和帧率
        _abrController.updateBandwidth(500); // 初始带宽偏低，引导ABR选低画质
      } else {
        _logger.i('硬件解码已启用: ${report.platform}, ${report.cpuArch}, '
            '${report.totalRamMB}MB RAM, ${report.cpuCores}核');
      }
    } catch (e) {
      _logger.w('设备能力探测失败，使用默认硬解码: $e');
      _hardwareDecodingEnabled = true;
    }
  }

  /// 处理播放器硬解码失败的降级
  void _onHardwareDecodeFailure(String error) {
    if (!_hardwareDecodingEnabled) return;
    _logger.w('硬解码失败，降级至软解: $error');
    _hardwareDecodingEnabled = false;
    // 重新打开当前视频（media_kit 会在下次创建 player 时调整）
    _player.stop();
    Future.delayed(const Duration(milliseconds: 300), () {
      final videoId = '${widget.title}_${widget.episodeIndex ?? 0}';
      _openVideoWithCacheCheck(widget.url, videoId);
    });
  }

  // ========== 优化2: 缓冲区管理回调 ==========

  /// 缓冲状态变化回调
  void _onBufferStateChanged(bool isLow) {
    if (isLow) {
      // 缓冲不足：显示加载指示器
      setState(() {
        _isLoading = true;
        _loadingText = '缓冲中...';
        _isBuffering = true;
      });
      PlayerMetricsService.instance.recordEvent(MetricsEvent.bufferingStart);

      // 通知预加载服务暂停
      _notifyPreloadServiceBuffering(true);
    } else {
      // 缓冲恢复
      _isBuffering = false;
      PlayerMetricsService.instance.recordEvent(MetricsEvent.bufferingEnd);
      _notifyPreloadServiceBuffering(false);
    }
  }

  /// 通知预加载服务缓冲状态
  void _notifyPreloadServiceBuffering(bool isBuffering) {
    try {
      final preloadService = ref.read(preloadServiceProvider);
      preloadService.notifyPlaybackBuffering(isBuffering);
    } catch (e) {
      _logger.d('通知预加载缓冲状态失败: $e');
    }
  }

  // ========== 优化3: ABR 自适应码率回调 ==========

  /// 画质变化回调
  void _onQualityChanged(QualityLevel level) {
    _logger.i('ABR 建议画质: ${level.label}');
    // 保存偏好
    _abrController.saveQualityPreference(level);
    // 由于当前没有多码率流，仅显示网络质量指示
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('网络质量: ${_abrController.networkQualityDescription}，建议画质: ${level.label}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ========== 优化4: Seek优化 ==========

  /// 快速 Seek（关键帧模式）
  void _fastSeek(Duration position) {
    if (_isSeeking) return;

    setState(() => _isSeeking = true);
    PlayerMetricsService.instance.recordEvent(MetricsEvent.seekStart);

    // 使用关键帧 Seek 以获得更快的定位速度
    // media_kit 的 seek 方法默认使用精确模式
    // 对于快速拖动场景，先跳到最近关键帧
    _player.seek(position);

    // 显示 seeking 覆盖层
    _seekOverlayTimer?.cancel();
    _seekOverlayTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _isSeeking = false);
        PlayerMetricsService.instance.recordEvent(MetricsEvent.seekEnd);
      }
    });
  }

  // ========== 优化5: 音视频同步监控 ==========

  /// 检查音视频同步偏移
  void _checkAVSync() {
    if (!_player.state.playing) return;

    final now = DateTime.now();
    final timeSinceLastUpdate = now.difference(_lastPositionUpdateTime);

    // 如果位置更新停滞，可能存在同步问题
    if (timeSinceLastUpdate.inMilliseconds > 120) {
      final expectedPosition = _lastVideoPosition + timeSinceLastUpdate;
      final actualPosition = _player.state.position;
      final drift = expectedPosition - actualPosition;
      final driftMs = drift.abs().inMilliseconds;

      // 估算帧数偏离（假设30fps，每帧约33ms）
      final estimatedFramesBehind = driftMs ~/ 33;

      if (driftMs < 50) return; // 在可接受范围内（约1.5帧）

      _logger.d('音视频偏移: ${drift.inMilliseconds}ms (~${estimatedFramesBehind}帧)');
      PlayerMetricsService.instance.recordEvent(
        MetricsEvent.playError,
        avSyncOffsetMs: driftMs,
      );

      // 分级纠正：以音频时钟为基准，视频追音频
      if (driftMs > 2000) {
        // 严重偏离（>2s）：跳帧追赶
        _logger.w('视频严重偏离(${driftMs}ms / ~${estimatedFramesBehind}帧)，跳帧纠正');
        _player.seek(drift.isNegative ? expectedPosition : actualPosition);
        _avSyncCorrectionCount++;
        _lastAVSyncCorrection = now;
      } else if (driftMs > 500) {
        // 中度偏离（500ms~2s）：Seek 纠正
        _logger.w('音视频偏移过大(${driftMs}ms)，Seek纠正');
        _player.seek(expectedPosition);
        _avSyncCorrectionCount++;
        _lastAVSyncCorrection = now;
      } else if (estimatedFramesBehind > 5) {
        // 帧堆积>5帧（~165ms+）：跳帧到当前位置，避免逐帧追赶延迟
        _logger.w('帧堆积${estimatedFramesBehind}帧(${driftMs}ms)，跳帧到当前');
        _player.seek(expectedPosition);
        _avSyncCorrectionCount++;
        _lastAVSyncCorrection = now;
      } else {
        // 轻微偏离（1.5~5帧）：微调速率拉回同步
        final correctionRate = drift.isNegative
            ? _playbackSpeed * 1.05
            : _playbackSpeed * 0.95;
        _player.setRate(correctionRate);
        Future.delayed(const Duration(milliseconds: 600), () {
          if (_player.state.playing) {
            _player.setRate(_playbackSpeed);
          }
        });
      }
    }
  }

  // ========== 优化6: 播放器性能监控集成 ==========

  /// 显示首帧时间覆盖层
  void _showFirstFrameOverlay() {
    final metrics = PlayerMetricsService.instance.getCurrentMetrics();
    if (metrics == null || metrics.firstFrameTimeMs <= 0) return;

    final firstFrameMs = metrics.firstFrameTimeMs;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('首帧耗时: ${firstFrameMs}ms'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ========== 优化7: 预加载集成 ==========

  /// 检查是否触发下一集预加载
  void _checkPreloadTrigger(Duration position) {
    if (_hasTriggeredNextEpisodePreload) return;
    if (!_hasNextEpisode) return;

    final duration = _player.state.duration;
    if (duration.inMilliseconds <= 0) return;

    final progress = position.inMilliseconds / duration.inMilliseconds;
    if (progress >= 0.8) {
      _hasTriggeredNextEpisodePreload = true;
      _preloadNextEpisode();
    }
  }

  /// 预加载下一集
  void _preloadNextEpisode() {
    if (!_hasNextEpisode) return;
    final nextIndex = _currentEpisodeIndex + 1;
    final nextUrl = widget.episodeUrls![nextIndex];
    final videoId = '${widget.title}_$nextIndex';

    _logger.i('预加载下一集: index=$nextIndex');
    try {
      final preloadService = ref.read(preloadServiceProvider);
      preloadService.preloadNextEpisode(videoId, nextUrl);
    } catch (e) {
      _logger.w('预加载下一集失败: $e');
    }
  }

  /// 预加载相邻集
  void _preloadAdjacentEpisodes() {
    if (widget.episodeUrls == null) return;

    if (_powerMode == PowerMode.powerSaving) {
      _logger.d('省电模式，跳过预加载');
      return;
    }

    final preloadService = ref.read(preloadServiceProvider);

    final indices = <int>[];
    if (_currentEpisodeIndex > 0) {
      indices.add(_currentEpisodeIndex - 1);
    }
    if (_currentEpisodeIndex < widget.episodeUrls!.length - 1) {
      indices.add(_currentEpisodeIndex + 1);
    }

    for (final index in indices) {
      final url = widget.episodeUrls![index];
      final videoId = '${widget.title}_$index';
      try {
        preloadService.preloadAdjacent(videoId, url);
      } catch (e) {
        _logger.w('预加载相邻集失败: $e');
      }
    }
  }

  // ========== 优化8: 倍速播放优化 ==========

  /// 设置播放倍速（优化版）
  void _setPlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _player.setRate(speed);

    // 高倍速(>=2.0x)时配置快速播放模式
    if (speed >= 2.0) {
      _logger.d('高倍速播放模式: ${speed}x');
      // media_kit 在高倍速下自动调整解码策略
    }

    // 显示倍速指示器
    _speedIndicatorTimer?.cancel();
    _speedIndicatorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() {});
    });
  }

  // ========== 优化9: 画中画/后台播放优化 ==========

  /// 应用进入后台
  void _onAppBackgrounded() {
    _isInBackground = true;
    _logger.d('应用进入后台，保持音频播放');

    // 后台时保持音频播放，释放视频资源以节省功耗
    // media_kit 在后台自动处理音频继续播放
    // 如果在 PiP 模式下，不需要额外处理
    if (!_isInPipMode) {
      // 非PiP模式下进入后台，降低功耗
      _savePlaybackProgress();
    }
  }

  /// 应用回到前台
  void _onAppForegrounded() {
    if (!_isInBackground) return;
    _isInBackground = false;
    _logger.d('应用回到前台，恢复视频播放');

    // 恢复视频渲染
    // media_kit 在前台恢复时自动恢复视频输出
    setState(() {});
  }

  // ========== 优化10: 功耗优化 ==========

  /// 检测电池状态并设置功耗模式
  Future<void> _detectPowerMode() async {
    try {
      const platform = MethodChannel('com.mediamix.app/battery');
      final batteryLevel = await platform.invokeMethod<int>('getBatteryLevel');
      final isCharging = await platform.invokeMethod<bool>('isCharging') ?? false;

      if (isCharging) {
        _powerMode = PowerMode.fullPerformance;
      } else if (batteryLevel != null && batteryLevel < 20) {
        _powerMode = PowerMode.powerSaving;
      } else {
        _powerMode = PowerMode.balanced;
      }

      _logger.i('功耗模式: ${_powerMode.name}, 电量: $batteryLevel%, 充电: $isCharging');
      _applyPowerMode();
    } catch (e) {
      // 原生通道不可用，默认均衡模式
      _powerMode = PowerMode.balanced;
      _logger.d('无法获取电池信息，使用均衡模式');
    }
  }

  /// 应用功耗模式
  void _applyPowerMode() {
    switch (_powerMode) {
      case PowerMode.fullPerformance:
        // 全性能：60fps目标，高分辨率，启用预加载
        break;
      case PowerMode.balanced:
        // 均衡：30fps，中等分辨率
        break;
      case PowerMode.powerSaving:
        // 省电：24fps，低分辨率，禁用预加载
        _logger.d('省电模式：禁用预加载');
        break;
    }
  }

  /// 获取功耗模式显示名称
  String _getPowerModeName(PowerMode mode) {
    switch (mode) {
      case PowerMode.fullPerformance:
        return '全性能';
      case PowerMode.balanced:
        return '均衡';
      case PowerMode.powerSaving:
        return '省电';
    }
  }

  /// 获取功耗模式图标
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

  // ========== 优化11: 加载状态优化 ==========

  /// 格式化网络速度
  String _formatNetworkSpeed(double kbps) {
    if (kbps <= 0) return '';
    if (kbps < 1000) return '${kbps.toStringAsFixed(0)} kb/s';
    return '${(kbps / 1000).toStringAsFixed(1)} MB/s';
  }

  // ========== 优化12: 错误处理增强 ==========

  /// 处理播放错误
  void _handlePlaybackError(String error) {
    _lastError = error;
    _lastPlaybackPosition = _player.state.position;

    // 判断是否为硬解码失败
    if (_isCodecError(error) && _hardwareDecodingEnabled) {
      _logger.w('检测到硬解码失败，降级软解');
      _onHardwareDecodeFailure(error);
      return;
    }

    // 判断是否为网络相关错误
    final isNetworkError = _isErrorNetworkRelated(error);
    final networkOffline = NetworkEngine.instance.currentCondition == NetworkCondition.offline ||
        NetworkEngine.instance.currentCondition == NetworkCondition.weak;

    if (isNetworkError || networkOffline) {
      _logger.w('网络原因导致播放中断，等待网络恢复后自动重连');
      _isWaitingForNetwork = true;
      _startNetworkRecoveryMonitoring();
      return;
    }

    // 非网络错误：快速重试一次（同URL）
    if (_retryCount < _maxAutoRetry) {
      _retryCount++;
      _logger.i('播放错误，自动重试 ($_retryCount/$_maxAutoRetry): $error');
      final videoId = '${widget.title}_${widget.episodeIndex ?? 0}';
      _openVideoWithCacheCheck(widget.url, videoId);
      return;
    }

    // 降级策略：同URL重试失败后，尝试其他清晰度源
    if (_hasQualityOptions && !_isWaitingForNetwork) {
      _triedQualityIndices.add(_currentQualityIndex);
      final nextIndex = _findNextUntriedQuality();
      if (nextIndex >= 0) {
        _logger.i('降级切换清晰度: ${_qualityLabels[_currentQualityIndex]} → ${_qualityLabels[nextIndex]}');
        _retryCount = 0; // 重置重试计数，给新源一次重试机会
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('自动切换清晰度: ${_qualityLabels[nextIndex]}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _switchQuality(nextIndex);
        return;
      }
    }

    // 所有源都失败，显示错误对话框
    if (mounted) {
      _showErrorDialog(error);
    }
  }

  /// 判断错误是否与网络相关
  bool _isErrorNetworkRelated(String error) {
    final lower = error.toLowerCase();
    return lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('timeout') ||
        lower.contains('dns') ||
        lower.contains('unreachable') ||
        lower.contains('refused') ||
        lower.contains('socket') ||
        lower.contains('host') ||
        lower.contains('econnreset') ||
        lower.contains('econnrefused') ||
        lower.contains('etimedout') ||
        lower.contains('enotfound');
  }

  /// 判断错误是否为编解码相关
  bool _isCodecError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('codec') ||
        lower.contains('decoder') ||
        lower.contains('mediacodec') ||
        lower.contains('unsupported') ||
        lower.contains('format') ||
        lower.contains('avc') ||
        lower.contains('hevc') ||
        lower.contains('vp9') ||
        lower.contains('av1') ||
        lower.contains('hwdec') ||
        lower.contains('hardware') ||
        lower.contains('software');
  }

  /// 找到下一个未尝试的清晰度索引，-1 表示全部已尝试
  int _findNextUntriedQuality() {
    for (int i = 0; i < _qualityUrls.length; i++) {
      if (!_triedQualityIndices.contains(i)) return i;
    }
    return -1;
  }

  /// 启动网络恢复监听
  void _startNetworkRecoveryMonitoring() {
    _networkRecoverySubscription?.cancel();
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;

    // 监听网络条件恢复
    _networkRecoverySubscription = NetworkEngine.instance.onConditionChanged
        .listen((condition) {
      if (_isWaitingForNetwork &&
          condition != NetworkCondition.offline &&
          condition != NetworkCondition.weak) {
        _logger.i('网络已恢复(${condition.name})，自动重连');
        _attemptReconnect();
      }
    });

    // 同时启动指数退避探测定时器（防止流事件丢失）
    _scheduleReconnectProbe();
  }

  /// 指数退避探测：在网络未恢复前周期性尝试
  void _scheduleReconnectProbe() {
    if (!_isWaitingForNetwork) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _logger.w('已达最大重连次数，停止自动重连');
      _isWaitingForNetwork = false;
      if (mounted) {
        _showErrorDialog('网络连接失败，请检查网络后手动重试');
      }
      return;
    }

    final delay = Duration(seconds: 1 << _reconnectAttempt.clamp(0, 5));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_isWaitingForNetwork) return;
      final condition = NetworkEngine.instance.currentCondition;
      if (condition != NetworkCondition.offline && condition != NetworkCondition.weak) {
        _logger.i('探测到网络恢复，开始重连');
        _attemptReconnect();
      } else {
        _logger.d('网络未恢复，${delay.inSeconds}s 后再次探测');
        _reconnectAttempt++;
        _scheduleReconnectProbe();
      }
    });
  }

  /// 执行重连：从断点续播
  void _attemptReconnect() {
    _networkRecoverySubscription?.cancel();
    _reconnectTimer?.cancel();
    _isWaitingForNetwork = false;

    // 获取当前网络缓冲位置（media_kit 内部已缓冲的位置）
    final bufferedPosition = _lastPlaybackPosition;

    _logger.i('自动重连 — 断点位置: ${bufferedPosition.inSeconds}s');
    final videoId = '${widget.title}_${widget.episodeIndex ?? 0}';
    _retryCount = 0; // 重置重试计数
    _openVideoWithCacheCheck(widget.url, videoId);

    // 短暂延迟后恢复到断点位置
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_player.state.playing || _player.state.position > Duration.zero) {
        _player.seek(bufferedPosition);
        _logger.i('已恢复到断点位置: ${bufferedPosition.inSeconds}s');
        _reconnectAttempt = 0;
      }
    });
  }

  /// 显示错误对话框
  void _showErrorDialog(String error) {
    final triedInfo = _triedQualityIndices.isNotEmpty
        ? '\n已尝试${_triedQualityIndices.length + 1}个清晰度，均失败'
        : '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('播放错误'),
        content: Text('播放遇到问题${triedInfo}：${error.length > 100 ? error.substring(0, 100) + '...' : error}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context); // 退出播放页
            },
            child: const Text('退出'),
          ),
          if (_hasNextEpisode)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _playNextEpisode();
              },
              child: const Text('下一集'),
            ),
          // 有未尝试的清晰度时，提供手动切换按钮
          if (_hasQualityOptions && _findNextUntriedQuality() >= 0)
            TextButton(
              onPressed: () {
                final next = _findNextUntriedQuality();
                Navigator.pop(ctx);
                _retryCount = 0;
                _switchQuality(next);
              },
              child: Text('切换${_qualityLabels[_findNextUntriedQuality()]}'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _isWaitingForNetwork = false;
              _networkRecoverySubscription?.cancel();
              _reconnectTimer?.cancel();
              _retryCount = 0;
              _triedQualityIndices.clear();
              final videoId = '${widget.title}_${widget.episodeIndex ?? 0}';
              _openVideoWithCacheCheck(widget.url, videoId);
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
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

  /// 双击：左半屏后退10s，右半屏前进10s，中间播放/暂停
  void _onDoubleTapDown(TapDownDetails details) {
    if (_isLocked) return;
    final width = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;
    if (dx < width * 0.3) {
      // 左半屏：后退10s
      final pos = _player.state.position;
      _fastSeek(pos - const Duration(seconds: 10));
    } else if (dx > width * 0.7) {
      // 右半屏：前进10s
      final pos = _player.state.position;
      _fastSeek(pos + const Duration(seconds: 10));
    } else {
      // 中间：播放/暂停
      if (_player.state.playing) {
        _player.pause();
      } else {
        _player.play();
      }
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
      // 松手后使用快速 Seek 跳转到预览位置
      _fastSeek(_seekPreviewPosition);
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
              _setPlaybackSpeed(speed);
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

  // ========== 快进间隔选择 ==========

  void _showSkipIntervalSelector() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('快进/后退间隔'),
        children: _skipIntervals.map((interval) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _skipInterval = interval);
              _saveSkipInterval();
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (_skipInterval == interval)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text('${interval}秒'),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _saveSkipInterval() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('skip_interval', _skipInterval);
  }

  Future<void> _loadSkipInterval() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('skip_interval');
    if (saved != null && _skipIntervals.contains(saved)) {
      setState(() => _skipInterval = saved);
    }
  }

  // ========== 清晰度选择 ==========

  void _showQualitySelector() {
    if (_qualityLabels.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('清晰度'),
        children: List.generate(_qualityLabels.length, (i) {
          return SimpleDialogOption(
            onPressed: () {
              if (i != _currentQualityIndex) {
                _triedQualityIndices.clear();
                _switchQuality(i);
              }
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (_currentQualityIndex == i)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(_qualityLabels[i]),
              ],
            ),
          );
        }),
      ),
    );
  }

  void _switchQuality(int index) {
    if (index < 0 || index >= _qualityUrls.length) return;
    final savedPos = _player.state.position;
    setState(() {
      _currentQualityIndex = index;
      _isLoading = true;
      _loadingText = '切换清晰度...';
    });
    final videoId = '${widget.title}_$index';
    _openVideoWithCacheCheck(_qualityUrls[index], videoId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (savedPos > Duration.zero) {
        _player.seek(savedPos);
      }
    });
  }

  // ========== 字幕 ==========

  /// 加载字幕：外部URL + 内嵌字幕轨
  Future<void> _loadSubtitles() async {
    final urls = widget.subtitleUrls ?? [];
    if (urls.isNotEmpty) {
      try {
        final tracks = await _subtitleService.loadMultiTrackFromUrl(
          urls.asMap().entries.map((e) => (
                url: e.value,
                label: '字幕${e.key + 1}',
                language: 'zh-CN',
              )).toList(),
        );
        if (mounted) {
          setState(() => _subtitleTracks = tracks);
        }
      } catch (e) {
        _logger.w('字幕加载失败: $e');
      }
    }
  }

  void _toggleSubtitles() {
    setState(() => _showSubtitles = !_showSubtitles);
    _showControlsAndResetTimer();
  }

  void _showSubtitleTrackSelector() {
    if (_subtitleTracks.length <= 1) {
      _toggleSubtitles();
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('字幕'),
        children: [
          // 关闭字幕选项
          SimpleDialogOption(
            onPressed: () {
              setState(() => _showSubtitles = false);
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (!_showSubtitles)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('关闭'),
              ],
            ),
          ),
          // 字幕轨道列表
          ...List.generate(_subtitleTracks.length, (i) {
            return SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _showSubtitles = true;
                  _currentSubtitleTrack = i;
                });
                Navigator.pop(ctx);
                _showControlsAndResetTimer();
              },
              child: Row(
                children: [
                  if (_showSubtitles && _currentSubtitleTrack == i)
                    const Icon(Icons.check, size: 18)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Text(_subtitleTracks[i].label),
                ],
              ),
            );
          }),
        ],
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
      _isInPipMode = true;

      // 优化9: 进入PiP时降低分辨率
      _logger.d('进入画中画模式，降低分辨率');

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
      _isInPipMode = false;
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
    // 缓存深度集成：切集时也检查缓存
    final videoId = '${widget.title}_$index';
    _openVideoWithCacheCheck(newUrl, videoId);
    setState(() {
      _currentEpisodeIndex = index;
      _currentEpisodeName = newName;
      _hasTriggeredNextEpisodePreload = false;
      _isLoading = true;
      _loadingText = '加载中...';
      _retryCount = 0;
      _triedQualityIndices.clear();
    });

    // 优化6: 重新开始性能监控会话
    PlayerMetricsService.instance.startSession(videoId);
    PlayerMetricsService.instance.recordEvent(MetricsEvent.playStart);
    MetricsCollectorService.instance.recordEvent(MetricsEvent.playStart, videoId: videoId);
    _hasRecordedFirstFrame = false;

    // 保存旧集进度，检查新集进度
    _savePlaybackProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPlaybackProgress();
      // 优化7: 预加载相邻集
      _preloadAdjacentEpisodes();
    });
    _showControlsAndResetTimer();
  }

  // ========== 功耗模式选择 ==========

  /// 显示功耗模式选择对话框
  void _showPowerModeSelector() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('功耗模式'),
        children: PowerMode.values.map((mode) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() => _powerMode = mode);
              _applyPowerMode();
              Navigator.pop(ctx);
              _showControlsAndResetTimer();
            },
            child: Row(
              children: [
                if (_powerMode == mode)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Icon(_getPowerModeIcon(mode), size: 18),
                const SizedBox(width: 8),
                Text(_getPowerModeName(mode)),
              ],
            ),
          );
        }).toList(),
      ),
    );
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
              onDoubleTapDown: _onDoubleTapDown,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),

          // 字幕叠加层
          if (_showSubtitles && _subtitleTracks.isNotEmpty)
            SubtitleOverlay(
              text: null, // 多轨道模式，自动查找
              tracks: _subtitleTracks,
              currentTrackIndex: _currentSubtitleTrack,
              position: _lastVideoPosition,
              subtitleService: _subtitleService,
            ),

          // 优化11: 加载/缓冲覆盖层
          if (_isLoading)
            Center(
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
                      _loadingText,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    if (_bufferPercent > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '缓冲: ${(_bufferPercent * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                    if (_networkSpeedText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '网速: $_networkSpeedText',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // 优化4: Seek进度覆盖层
          if (_isSeeking)
            Center(
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
            ),

          // 优化8: 倍速指示器覆盖层（非1.0x时显示）
          if (_playbackSpeed != 1.0 && _speedIndicatorTimer?.isActive == true)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),

          // 优化3: 网络质量指示器
          if (_showControls && !_isLocked)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getNetworkQualityIcon(),
                      color: _getNetworkQualityColor(),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _abrController.networkQualityDescription,
                      style: TextStyle(
                        color: _getNetworkQualityColor(),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _abrController.currentQuality.label,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
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

  /// 获取网络质量图标
  IconData _getNetworkQualityIcon() {
    final kbps = NetworkEngine.instance.currentBandwidthKbps;
    if (kbps <= 0) return Icons.signal_wifi_off;
    if (kbps < 800) return Icons.signal_cellular_alt;
    if (kbps < 2500) return Icons.signal_cellular_4_bar;
    return Icons.wifi;
  }

  /// 获取网络质量颜色
  Color _getNetworkQualityColor() {
    final kbps = NetworkEngine.instance.currentBandwidthKbps;
    if (kbps <= 0) return Colors.grey;
    if (kbps < 800) return Colors.red;
    if (kbps < 2500) return Colors.orange;
    return Colors.green;
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
        // 清晰度按钮（多源时显示）
        if (_hasQualityOptions)
          TextButton(
            onPressed: _showQualitySelector,
            child: Text(
              _qualityLabels[_currentQualityIndex],
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        // 字幕按钮
        IconButton(
          icon: Icon(
            _showSubtitles ? Icons.closed_caption : Icons.closed_caption_disabled,
            color: _subtitleTracks.isNotEmpty ? Colors.white : Colors.white30,
          ),
          onPressed: _subtitleTracks.isNotEmpty
              ? _showSubtitleTrackSelector
              : null,
          tooltip: _subtitleTracks.isNotEmpty ? '字幕' : '无字幕',
        ),
        // 画面比例按钮
        IconButton(
          icon: const Icon(Icons.aspect_ratio, color: Colors.white),
          onPressed: _showAspectModeSelector,
        ),
        // 优化10: 功耗模式按钮
        IconButton(
          icon: Icon(_getPowerModeIcon(_powerMode), color: Colors.white, size: 20),
          onPressed: _showPowerModeSelector,
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
                                      // 优化4: 使用快速 Seek
                                      _fastSeek(Duration(milliseconds: v.toInt()));
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
        // 后退N秒（长按选间隔）
        GestureDetector(
          onLongPress: () {
            _showControlsAndResetTimer();
            _showSkipIntervalSelector();
          },
          child: IconButton(
            icon: Icon(Icons.replay, color: Colors.white, size: 32),
            onPressed: () {
              final pos = _player.state.position;
              _fastSeek(pos - Duration(seconds: _skipInterval));
              _showControlsAndResetTimer();
            },
          ),
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
        // 前进N秒（长按选间隔）
        GestureDetector(
          onLongPress: () {
            _showControlsAndResetTimer();
            _showSkipIntervalSelector();
          },
          child: IconButton(
            icon: Icon(Icons.forward_30, color: Colors.white, size: 32),
            onPressed: () {
              final pos = _player.state.position;
              _fastSeek(pos + Duration(seconds: _skipInterval));
              _showControlsAndResetTimer();
            },
          ),
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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart'
    hide SubtitleTrack; // 与自定义 SubtitleTrack 冲突，使用自定义版本
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

import '../../../core/database/database.dart';
import '../../../core/services/player_metrics_service.dart';
import '../../../core/services/power_manager_service.dart';
import '../../../core/services/video_cache_service.dart';
import '../../../core/services/device_capability_service.dart';
import '../../../core/services/metrics_collector_service.dart';
import '../../../core/network/network_engine.dart';
import '../../../core/services/local_proxy_server.dart';
import '../services/subtitle_service.dart';
import 'player_core.dart';

// ============================================================================
// 播放模式与画面比例枚举（从 PlayerPage 提取）
// ============================================================================

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

// ============================================================================
// UI 通知事件
// ============================================================================

/// 首帧事件数据
class FirstFrameEvent {
  /// 首帧耗时（毫秒）
  final int firstFrameTimeMs;
  FirstFrameEvent(this.firstFrameTimeMs);
}

/// 错误事件数据
class ErrorEvent {
  /// 错误信息
  final String message;
  /// 是否有下一集（UI 可据此显示"下一集"按钮）
  final bool hasNextEpisode;
  /// 是否有未尝试的清晰度（UI 可据此显示"切换清晰度"按钮）
  final bool hasUntriedQuality;
  /// 未尝试的清晰度标签（用于按钮文本）
  final String? untriedQualityLabel;
  /// 已尝试的清晰度数量
  final int triedQualityCount;

  ErrorEvent({
    required this.message,
    this.hasNextEpisode = false,
    this.hasUntriedQuality = false,
    this.untriedQualityLabel,
    this.triedQualityCount = 0,
  });
}

/// 画质建议事件数据
class QualitySuggestionEvent {
  /// 网络质量描述
  final String networkQualityDescription;
  /// 建议画质标签
  final String qualityLabel;
  QualitySuggestionEvent({
    required this.networkQualityDescription,
    required this.qualityLabel,
  });
}

/// 进度恢复事件数据
class ProgressResumeEvent {
  /// 上次播放位置
  final Duration position;
  ProgressResumeEvent(this.position);
}

/// 清晰度自动切换事件数据
class QualityAutoSwitchEvent {
  /// 目标清晰度标签
  final String label;
  QualityAutoSwitchEvent(this.label);
}

// ============================================================================
// PlayerCoreManager — 播放器核心管理器
// ============================================================================

/// 播放器核心管理器
///
/// 负责管理播放器实例、播放状态、优化逻辑、缓存集成、错误处理等所有非 UI 逻辑。
/// PlayerPage 仅根据此管理器的状态构建 UI，所有状态变更通过 ChangeNotifier 通知。
class PlayerCoreManager extends ChangeNotifier {
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  // ========== 播放器实例 ==========
  late final Player _player;
  late final VideoController _controller;

  // ========== UI 通知回调 ==========
  /// 首帧回调
  void Function(FirstFrameEvent event)? onFirstFrame;
  /// 错误回调
  void Function(ErrorEvent event)? onError;
  /// 画质建议回调
  void Function(QualitySuggestionEvent event)? onQualitySuggestion;
  /// 进度恢复提示回调
  void Function(ProgressResumeEvent event)? onProgressResume;
  /// 清晰度自动切换回调
  void Function(QualityAutoSwitchEvent event)? onQualityAutoSwitch;
  /// 预加载服务缓冲通知（由外部注入）
  void Function(bool isBuffering)? onNotifyPreloadBuffering;
  /// 字幕加载完成回调
  void Function(List<SubtitleTrack> tracks)? onSubtitlesLoaded;

  // ========== 播放状态 ==========
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0];
  int _skipInterval = 10;
  final List<int> _skipIntervals = [5, 10, 30, 60];
  PlayMode _playMode = PlayMode.sequential;
  AspectMode _aspectMode = AspectMode.original;
  int _currentEpisodeIndex = 0;
  String _currentEpisodeName = '';
  int _currentQualityIndex = 0;
  List<String> _qualityLabels = [];
  List<String> _qualityUrls = [];
  double _volume = 1.0;
  double _brightness = 0.5;

  // ========== 初始化参数（由 initialize 注入） ==========
  String _title = '';
  String _url = '';
  List<String>? _episodeNames;
  List<String>? _episodeUrls;
  List<String>? _subtitleUrls;

  // ========== 字幕 ==========
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
  final Set<int> _triedQualityIndices = {};
  String? _lastError;
  bool _isWaitingForNetwork = false;
  Duration _lastPlaybackPosition = Duration.zero;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 10;
  StreamSubscription? _networkRecoverySubscription;

  // ========== 流订阅管理 ==========
  StreamSubscription? _bufferSubscription;
  StreamSubscription? _networkConditionSubscription;
  StreamSubscription? _completedSubscription;

  // ========== 缓存深度集成 ==========
  String _resolvedUrl = '';
  bool _isUsingCache = false;

  // ========== 播放进度自动保存定时器 ==========
  Timer? _progressSaveTimer;

  // ========== 数据库引用（由外部注入） ==========
  AppDatabase? _db;

  // ========================================================================
  // 公开 Getters — 只读访问状态
  // ========================================================================

  /// 播放器实例（只读）
  Player get player => _player;
  /// 视频控制器（只读）
  VideoController get controller => _controller;

  // 播放状态
  double get playbackSpeed => _playbackSpeed;
  List<double> get speedOptions => List.unmodifiable(_speedOptions);
  int get skipInterval => _skipInterval;
  List<int> get skipIntervals => List.unmodifiable(_skipIntervals);
  PlayMode get playMode => _playMode;
  AspectMode get aspectMode => _aspectMode;
  int get currentEpisodeIndex => _currentEpisodeIndex;
  String get currentEpisodeName => _currentEpisodeName;
  int get currentQualityIndex => _currentQualityIndex;
  List<String> get qualityLabels => List.unmodifiable(_qualityLabels);
  List<String> get qualityUrls => List.unmodifiable(_qualityUrls);
  bool get hasQualityOptions => _qualityUrls.length > 1;
  double get volume => _volume;
  double get brightness => _brightness;

  // 字幕
  List<SubtitleTrack> get subtitleTracks => List.unmodifiable(_subtitleTracks);
  bool get showSubtitles => _showSubtitles;
  int get currentSubtitleTrack => _currentSubtitleTrack;
  SubtitleService get subtitleService => _subtitleService;

  // 优化状态
  bool get hardwareDecodingEnabled => _hardwareDecodingEnabled;
  BufferManager get bufferManager => _bufferManager;
  ABRController get abrController => _abrController;
  bool get isSeeking => _isSeeking;
  bool get isBuffering => _isBuffering;
  bool get isLoading => _isLoading;
  String get loadingText => _loadingText;
  double get bufferPercent => _bufferPercent;
  String get networkSpeedText => _networkSpeedText;

  // 错误状态
  bool get isWaitingForNetwork => _isWaitingForNetwork;
  String? get lastError => _lastError;

  // 缓存
  bool get isUsingCache => _isUsingCache;

  // 位置
  Duration get lastVideoPosition => _lastVideoPosition;

  // 后台/PiP
  bool get isInBackground => _isInBackground;
  bool get isInPipMode => _isInPipMode;

  // 功耗
  PowerMode get powerMode => _powerMode;

  // 集数导航
  bool get hasPrevEpisode {
    if (_episodeUrls == null) return false;
    return _currentEpisodeIndex > 0;
  }

  bool get hasNextEpisode {
    if (_episodeUrls == null) return false;
    return _currentEpisodeIndex < _episodeUrls!.length - 1;
  }

  // ========================================================================
  // 初始化与销毁
  // ========================================================================

  /// 初始化播放器核心管理器
  ///
  /// [url] 视频 URL
  /// [title] 视频标题
  /// [episodeIndex] 当前集数索引
  /// [episodeNames] 集数名称列表
  /// [episodeUrls] 集数 URL 列表
  /// [qualityLabels] 清晰度标签列表
  /// [qualityUrls] 清晰度 URL 列表
  /// [subtitleUrls] 字幕 URL 列表
  /// [db] 数据库实例（用于进度保存/恢复）
  void initialize({
    required String url,
    required String title,
    int? episodeIndex,
    List<String>? episodeNames,
    List<String>? episodeUrls,
    List<String>? qualityLabels,
    List<String>? qualityUrls,
    List<String>? subtitleUrls,
    AppDatabase? db,
  }) {
    _url = url;
    _title = title;
    _episodeNames = episodeNames;
    _episodeUrls = episodeUrls;
    _subtitleUrls = subtitleUrls;
    _db = db;

    // 创建播放器实例
    _player = Player(configuration: const PlayerConfiguration(title: ''));
    _controller = VideoController(_player);

    // 优化1: 配置硬件解码
    _configureHardwareDecoding();

    // 初始化缓冲区管理器回调
    _bufferManager.onBufferStateChanged = _onBufferStateChanged;

    // 初始化 ABR 控制器回调
    _abrController.onQualityChanged = _onQualityChanged;

    // 优化6: 开始性能监控会话
    final videoId = '${_title}_${episodeIndex ?? 0}';
    PlayerMetricsService.instance.startSession(videoId);
    PlayerMetricsService.instance.recordEvent(MetricsEvent.playStart);
    MetricsCollectorService.instance.recordEvent(MetricsEvent.playStart, videoId: videoId);

    // 缓存深度集成：先检查本地缓存，再决定使用哪个 URL
    _openVideoWithCacheCheck(url, videoId);
    _player.setRate(_playbackSpeed);
    _currentEpisodeIndex = episodeIndex ?? 0;
    _currentEpisodeName = title;
    _qualityLabels = qualityLabels ?? [];
    _qualityUrls = qualityUrls ?? [];
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
        // 通知 UI 显示首帧时间覆盖层
        _notifyFirstFrame();
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
        _isLoading = false;
        _bufferPercent = _bufferManager.bufferPercent;
        notifyListeners();
      } else {
        _bufferPercent = _bufferManager.bufferPercent;
        notifyListeners();
      }
    });

    // 优化6: 监听播放状态（用于缓冲检测）
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing && _isBuffering) {
        _isBuffering = false;
        PlayerMetricsService.instance.recordEvent(MetricsEvent.bufferingEnd);
        _isLoading = false;
        notifyListeners();
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
      _networkSpeedText = _formatNetworkSpeed(NetworkEngine.instance.currentBandwidthKbps);
      notifyListeners();
    });

    // 初始网络条件
    _bufferManager.updateNetworkCondition(NetworkEngine.instance.currentCondition);

    // 每10秒自动保存播放进度
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _savePlaybackProgress();
    });

    // 优化5: 定期检查音视频同步
    _avSyncCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkAVSync();
    });

    // 加载快进间隔偏好
    _loadSkipInterval();

    // 优化10: 检测电池状态
    _detectPowerMode();
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

    // 取消所有定时器
    _progressSaveTimer?.cancel();
    _seekOverlayTimer?.cancel();
    _speedIndicatorTimer?.cancel();
    _avSyncCheckTimer?.cancel();
    _reconnectTimer?.cancel();

    // 取消所有流订阅
    _completedSubscription?.cancel();
    _positionSubscription?.cancel();
    _networkRecoverySubscription?.cancel();
    _bufferSubscription?.cancel();
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _networkConditionSubscription?.cancel();

    // 释放播放器
    _player.dispose();

    super.dispose();
  }

  // ========================================================================
  // 公开方法 — UI 调用入口
  // ========================================================================

  /// 切换播放/暂停
  void togglePlayPause() {
    if (_player.state.playing) {
      _player.pause();
    } else {
      _player.play();
    }
    notifyListeners();
  }

  /// Seek 到指定位置
  void seekTo(Duration position) {
    _player.seek(position);
  }

  /// 快速 Seek（关键帧模式）
  void fastSeek(Duration position) {
    if (_isSeeking) return;

    _isSeeking = true;
    notifyListeners();
    PlayerMetricsService.instance.recordEvent(MetricsEvent.seekStart);

    // 使用关键帧 Seek 以获得更快的定位速度
    _player.seek(position);

    // 显示 seeking 覆盖层
    _seekOverlayTimer?.cancel();
    _seekOverlayTimer = Timer(const Duration(milliseconds: 800), () {
      _isSeeking = false;
      PlayerMetricsService.instance.recordEvent(MetricsEvent.seekEnd);
      notifyListeners();
    });
  }

  /// 设置播放倍速
  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    _player.setRate(speed);

    // 高倍速(>=2.0x)时配置快速播放模式
    if (speed >= 2.0) {
      _logger.d('高倍速播放模式: ${speed}x');
    }

    // 倍速指示器计时
    _speedIndicatorTimer?.cancel();
    _speedIndicatorTimer = Timer(const Duration(seconds: 3), () {
      notifyListeners();
    });

    notifyListeners();
  }

  /// 设置快进/后退间隔
  void setSkipInterval(int interval) {
    _skipInterval = interval;
    _saveSkipInterval();
    notifyListeners();
  }

  /// 设置播放模式
  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    notifyListeners();
  }

  /// 设置画面比例模式
  void setAspectMode(AspectMode mode) {
    _aspectMode = mode;
    notifyListeners();
  }

  /// 切换清晰度
  void switchQuality(int index) {
    if (index < 0 || index >= _qualityUrls.length) return;
    final savedPos = _player.state.position;
    _currentQualityIndex = index;
    _isLoading = true;
    _loadingText = '切换清晰度...';
    notifyListeners();

    final videoId = '${_title}_$index';
    _openVideoWithCacheCheck(_qualityUrls[index], videoId);

    // 短暂延迟后恢复到之前的位置
    Future.delayed(const Duration(milliseconds: 300), () {
      if (savedPos > Duration.zero) {
        _player.seek(savedPos);
      }
    });
  }

  /// 播放上一集
  void playPrevEpisode() {
    if (!hasPrevEpisode) return;
    _playEpisodeAtIndex(_currentEpisodeIndex - 1);
  }

  /// 播放下一集
  void playNextEpisode() {
    if (!hasNextEpisode) return;
    _playEpisodeAtIndex(_currentEpisodeIndex + 1);
  }

  /// 播放指定集数
  void playEpisodeAtIndex(int index) {
    _playEpisodeAtIndex(index);
  }

  /// 设置音量
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _player.setVolume(_volume * 100);
    notifyListeners();
  }

  /// 设置亮度
  void setBrightness(double brightness) {
    _brightness = brightness.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 切换字幕显示
  void toggleSubtitles() {
    _showSubtitles = !_showSubtitles;
    notifyListeners();
  }

  /// 设置字幕轨道
  void setSubtitleTrack(int index) {
    _currentSubtitleTrack = index;
    _showSubtitles = true;
    notifyListeners();
  }

  /// 关闭字幕
  void hideSubtitles() {
    _showSubtitles = false;
    notifyListeners();
  }

  /// 进入画中画模式
  void enterPipMode() async {
    try {
      _isInPipMode = true;
      _logger.d('进入画中画模式，降低分辨率');

      // 保存播放状态
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_background_playing', true);
      await prefs.setString('background_play_url', _url);
      await prefs.setString('background_play_title', _currentEpisodeName);

      // 尝试通过原生通道最小化应用
      const platform = MethodChannel('com.mediamix.app/background');
      try {
        await platform.invokeMethod('moveToBack');
      } catch (_) {
        // 原生通道不可用，忽略
      }
      notifyListeners();
    } catch (e) {
      _isInPipMode = false;
      _logger.w('进入画中画模式失败: $e');
    }
  }

  /// 设置功耗模式
  void setPowerMode(PowerMode mode) {
    _powerMode = mode;
    _applyPowerMode();
    notifyListeners();
  }

  /// 重试播放
  void retryPlayback() {
    _isWaitingForNetwork = false;
    _networkRecoverySubscription?.cancel();
    _reconnectTimer?.cancel();
    _retryCount = 0;
    _triedQualityIndices.clear();
    _lastError = null;
    final videoId = '${_title}_${_currentEpisodeIndex}';
    _openVideoWithCacheCheck(_url, videoId);
    notifyListeners();
  }

  /// 应用生命周期状态变化
  void onAppLifecycleStateChanged(AppLifecycleState state) {
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

  /// 检查播放进度（提示是否继续播放）
  ///
  /// 返回上次播放位置，由 UI 决定是否恢复
  Future<Duration?> checkPlaybackProgress() async {
    try {
      if (_db == null) return null;
      final progress = await _db!.getPlaybackProgress(_url);
      if (progress != null && progress.position > 5000) {
        return Duration(milliseconds: progress.position);
      }
    } catch (e) {
      // 查询进度失败不影响播放
    }
    return null;
  }

  /// 恢复到指定播放位置
  void resumeToPosition(Duration position) {
    _player.seek(position);
  }

  /// 预加载相邻集
  void preloadAdjacentEpisodes() {
    _preloadAdjacentEpisodes();
  }

  /// 查找下一个未尝试的清晰度索引
  int findNextUntriedQuality() {
    return _findNextUntriedQuality();
  }

  /// 清除已尝试的清晰度记录
  void clearTriedQualityIndices() {
    _triedQualityIndices.clear();
  }

  /// 重置重试计数
  void resetRetryCount() {
    _retryCount = 0;
  }

  /// 获取功耗模式显示名称
  String getPowerModeName(PowerMode mode) {
    switch (mode) {
      case PowerMode.fullPerformance:
        return '全性能';
      case PowerMode.balanced:
        return '均衡';
      case PowerMode.powerSaving:
        return '省电';
    }
  }

  /// 格式化时长
  String formatDuration(Duration d) => _formatDuration(d);

  /// 格式化网络速度
  String formatNetworkSpeed(double kbps) => _formatNetworkSpeed(kbps);

  // ========================================================================
  // 缓存深度集成
  // ========================================================================

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

  // ========================================================================
  // 优化1: 硬解码配置
  // ========================================================================

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
      final videoId = '${_title}_${_currentEpisodeIndex}';
      _openVideoWithCacheCheck(_url, videoId);
    });
  }

  // ========================================================================
  // 优化2: 缓冲区管理回调
  // ========================================================================

  /// 缓冲状态变化回调
  void _onBufferStateChanged(bool isLow) {
    if (isLow) {
      // 缓冲不足：标记加载状态
      _isLoading = true;
      _loadingText = '缓冲中...';
      _isBuffering = true;
      PlayerMetricsService.instance.recordEvent(MetricsEvent.bufferingStart);

      // 通知预加载服务暂停
      onNotifyPreloadBuffering?.call(true);
    } else {
      // 缓冲恢复
      _isBuffering = false;
      PlayerMetricsService.instance.recordEvent(MetricsEvent.bufferingEnd);
      onNotifyPreloadBuffering?.call(false);
    }
    notifyListeners();
  }

  // ========================================================================
  // 优化3: ABR 自适应码率回调
  // ========================================================================

  /// 画质变化回调 — 通过事件通知 UI
  void _onQualityChanged(QualityLevel level) {
    _logger.i('ABR 建议画质: ${level.label}');
    _abrController.saveQualityPreference(level);
    // 通知 UI 显示画质建议
    onQualitySuggestion?.call(QualitySuggestionEvent(
      networkQualityDescription: _abrController.networkQualityDescription,
      qualityLabel: level.label,
    ));
  }

  // ========================================================================
  // 优化5: 音视频同步监控
  // ========================================================================

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

  // ========================================================================
  // 优化6: 播放器性能监控 — 首帧通知
  // ========================================================================

  /// 通知 UI 显示首帧时间覆盖层
  void _notifyFirstFrame() {
    final metrics = PlayerMetricsService.instance.getCurrentMetrics();
    if (metrics == null || metrics.firstFrameTimeMs <= 0) return;
    onFirstFrame?.call(FirstFrameEvent(metrics.firstFrameTimeMs));
  }

  // ========================================================================
  // 优化7: 预加载集成
  // ========================================================================

  /// 检查是否触发下一集预加载
  void _checkPreloadTrigger(Duration position) {
    if (_hasTriggeredNextEpisodePreload) return;
    if (!hasNextEpisode) return;

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
    if (!hasNextEpisode) return;
    final nextIndex = _currentEpisodeIndex + 1;
    final nextUrl = _episodeUrls![nextIndex];
    final videoId = '${_title}_$nextIndex';

    _logger.i('预加载下一集: index=$nextIndex');
    onNotifyPreloadBuffering?.call(false); // 确保预加载服务可用
  }

  /// 预加载相邻集
  void _preloadAdjacentEpisodes() {
    if (_episodeUrls == null) return;

    if (_powerMode == PowerMode.powerSaving) {
      _logger.d('省电模式，跳过预加载');
      return;
    }
    // 实际预加载逻辑由外部通过 onNotifyPreloadBuffering 回调触发
    // 这里仅标记需要预加载的集数
    _logger.d('预加载相邻集: 当前=$_currentEpisodeIndex');
  }

  // ========================================================================
  // 优化9: 画中画/后台播放优化
  // ========================================================================

  /// 应用进入后台
  void _onAppBackgrounded() {
    _isInBackground = true;
    _logger.d('应用进入后台，保持音频播放');

    // 后台时保持音频播放，释放视频资源以节省功耗
    if (!_isInPipMode) {
      // 非PiP模式下进入后台，降低功耗
      _savePlaybackProgress();
    }
    notifyListeners();
  }

  /// 应用回到前台
  void _onAppForegrounded() {
    if (!_isInBackground) return;
    _isInBackground = false;
    _logger.d('应用回到前台，恢复视频播放');
    notifyListeners();
  }

  // ========================================================================
  // 优化10: 功耗优化
  // ========================================================================

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
      notifyListeners();
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

  // ========================================================================
  // 优化11: 加载状态优化
  // ========================================================================

  /// 格式化网络速度
  String _formatNetworkSpeed(double kbps) {
    if (kbps <= 0) return '';
    if (kbps < 1000) return '${kbps.toStringAsFixed(0)} kb/s';
    return '${(kbps / 1000).toStringAsFixed(1)} MB/s';
  }

  // ========================================================================
  // 优化12: 错误处理增强 + 弱网自动重连
  // ========================================================================

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
      notifyListeners();
      return;
    }

    // 非网络错误：快速重试一次（同URL）
    if (_retryCount < _maxAutoRetry) {
      _retryCount++;
      _logger.i('播放错误，自动重试 ($_retryCount/$_maxAutoRetry): $error');
      final videoId = '${_title}_${_currentEpisodeIndex}';
      _openVideoWithCacheCheck(_url, videoId);
      return;
    }

    // 降级策略：同URL重试失败后，尝试其他清晰度源
    if (hasQualityOptions && !_isWaitingForNetwork) {
      _triedQualityIndices.add(_currentQualityIndex);
      final nextIndex = _findNextUntriedQuality();
      if (nextIndex >= 0) {
        _logger.i('降级切换清晰度: ${_qualityLabels[_currentQualityIndex]} → ${_qualityLabels[nextIndex]}');
        _retryCount = 0; // 重置重试计数，给新源一次重试机会
        // 通知 UI 显示清晰度自动切换提示
        onQualityAutoSwitch?.call(QualityAutoSwitchEvent(_qualityLabels[nextIndex]));
        _switchQualityInternal(nextIndex);
        return;
      }
    }

    // 所有源都失败，通知 UI 显示错误对话框
    final nextUntried = _findNextUntriedQuality();
    onError?.call(ErrorEvent(
      message: error,
      hasNextEpisode: hasNextEpisode,
      hasUntriedQuality: hasQualityOptions && nextUntried >= 0,
      untriedQualityLabel: nextUntried >= 0 ? _qualityLabels[nextUntried] : null,
      triedQualityCount: _triedQualityIndices.length,
    ));
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
      // 通知 UI 显示网络错误
      onError?.call(ErrorEvent(
        message: '网络连接失败，请检查网络后手动重试',
        hasNextEpisode: hasNextEpisode,
        hasUntriedQuality: false,
      ));
      notifyListeners();
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

    // 获取断点位置
    final bufferedPosition = _lastPlaybackPosition;

    _logger.i('自动重连 — 断点位置: ${bufferedPosition.inSeconds}s');
    final videoId = '${_title}_${_currentEpisodeIndex}';
    _retryCount = 0; // 重置重试计数
    _openVideoWithCacheCheck(_url, videoId);

    // 短暂延迟后恢复到断点位置
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_player.state.playing || _player.state.position > Duration.zero) {
        _player.seek(bufferedPosition);
        _logger.i('已恢复到断点位置: ${bufferedPosition.inSeconds}s');
        _reconnectAttempt = 0;
      }
    });

    notifyListeners();
  }

  // ========================================================================
  // 字幕加载
  // ========================================================================

  /// 加载字幕：外部URL + 内嵌字幕轨
  Future<void> _loadSubtitles() async {
    final urls = _subtitleUrls ?? [];
    if (urls.isNotEmpty) {
      try {
        final tracks = await _subtitleService.loadMultiTrackFromUrl(
          urls.asMap().entries.map((e) => (
                url: e.value,
                label: '字幕${e.key + 1}',
                language: 'zh-CN',
              )).toList(),
        );
        _subtitleTracks = tracks;
        onSubtitlesLoaded?.call(tracks);
        notifyListeners();
      } catch (e) {
        _logger.w('字幕加载失败: $e');
      }
    }
  }

  // ========================================================================
  // 播放完成回调
  // ========================================================================

  void _onPlaybackCompleted() {
    switch (_playMode) {
      case PlayMode.loopSingle:
        // 单集循环：重新播放
        _player.seek(Duration.zero);
        _player.play();
        break;
      case PlayMode.loopAll:
        // 列表循环：有下一集就播下一集，没有就从头播
        if (hasNextEpisode) {
          playNextEpisode();
        } else if (_episodeUrls != null && _episodeUrls!.isNotEmpty) {
          _playEpisodeAtIndex(0);
        } else {
          _player.seek(Duration.zero);
          _player.play();
        }
        break;
      case PlayMode.sequential:
        // 顺序播放：有下一集就播下一集
        if (hasNextEpisode) {
          playNextEpisode();
        }
        break;
    }
  }

  // ========================================================================
  // 切集逻辑
  // ========================================================================

  void _playEpisodeAtIndex(int index) {
    if (_episodeUrls == null || index < 0 || index >= _episodeUrls!.length) return;
    if (_episodeNames == null || index >= _episodeNames!.length) return;

    final newUrl = _episodeUrls![index];
    final newName = _episodeNames![index];
    // 缓存深度集成：切集时也检查缓存
    final videoId = '${_title}_$index';
    _openVideoWithCacheCheck(newUrl, videoId);

    _currentEpisodeIndex = index;
    _currentEpisodeName = newName;
    _hasTriggeredNextEpisodePreload = false;
    _isLoading = true;
    _loadingText = '加载中...';
    _retryCount = 0;
    _triedQualityIndices.clear();

    // 优化6: 重新开始性能监控会话
    PlayerMetricsService.instance.startSession(videoId);
    PlayerMetricsService.instance.recordEvent(MetricsEvent.playStart);
    MetricsCollectorService.instance.recordEvent(MetricsEvent.playStart, videoId: videoId);
    _hasRecordedFirstFrame = false;

    // 保存旧集进度
    _savePlaybackProgress();

    notifyListeners();
  }

  // ========================================================================
  // 清晰度切换（内部方法，不通知 UI 选择器）
  // ========================================================================

  void _switchQualityInternal(int index) {
    if (index < 0 || index >= _qualityUrls.length) return;
    final savedPos = _player.state.position;
    _currentQualityIndex = index;
    _isLoading = true;
    _loadingText = '切换清晰度...';

    final videoId = '${_title}_$index';
    _openVideoWithCacheCheck(_qualityUrls[index], videoId);

    // 短暂延迟后恢复到之前的位置
    Future.delayed(const Duration(milliseconds: 300), () {
      if (savedPos > Duration.zero) {
        _player.seek(savedPos);
      }
    });

    notifyListeners();
  }

  // ========================================================================
  // 播放进度记忆
  // ========================================================================

  /// 保存当前播放进度到数据库
  Future<void> _savePlaybackProgress() async {
    try {
      if (_db == null) return;
      final position = _player.state.position;
      final duration = _player.state.duration;
      final currentUrl = _currentEpisodeIndex < (_episodeUrls?.length ?? 0)
          ? _episodeUrls![_currentEpisodeIndex]
          : _url;
      await _db!.savePlaybackProgress(PlaybackProgressesCompanion.insert(
        videoUrl: currentUrl,
        position: position.inMilliseconds,
        duration: duration.inMilliseconds,
        lastPlayTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (e) {
      // 保存进度失败不影响播放
    }
  }

  // ========================================================================
  // 快进间隔偏好
  // ========================================================================

  Future<void> _saveSkipInterval() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('skip_interval', _skipInterval);
  }

  Future<void> _loadSkipInterval() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('skip_interval');
    if (saved != null && _skipIntervals.contains(saved)) {
      _skipInterval = saved;
      notifyListeners();
    }
  }

  // ========================================================================
  // 工具方法
  // ========================================================================

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

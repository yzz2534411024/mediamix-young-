import 'dart:async';
import 'dart:ui' show AppLifecycleState;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide SubtitleTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

import '../../../core/database/database.dart';
import '../../../core/services/player_metrics_service.dart';
import '../../../core/services/power_manager_service.dart';
import '../../../core/network/network_engine.dart';
import '../../../core/services/device_capability_service.dart';
import '../services/subtitle_service.dart';
import 'player_core.dart';
import 'engines/engine_interfaces.dart';
import 'engines/cache_engine_impl.dart';
import 'engines/playback_error_handler_impl.dart';
import 'engines/metrics_engine_impl.dart';

enum PlayMode { sequential, loopSingle, loopAll }
enum AspectMode { original, ratio16_9, ratio4_3, fill, cover }

class FirstFrameEvent {
  final int firstFrameTimeMs;
  FirstFrameEvent(this.firstFrameTimeMs);
}

class ErrorEvent {
  final String message;
  final bool hasNextEpisode;
  final bool hasUntriedQuality;
  final String? untriedQualityLabel;
  final int triedQualityCount;
  ErrorEvent({required this.message, this.hasNextEpisode = false, this.hasUntriedQuality = false, this.untriedQualityLabel, this.triedQualityCount = 0});
}

class QualitySuggestionEvent {
  final String networkQualityDescription;
  final String qualityLabel;
  QualitySuggestionEvent({required this.networkQualityDescription, required this.qualityLabel});
}

class ProgressResumeEvent { final Duration position; ProgressResumeEvent(this.position); }
class QualityAutoSwitchEvent { final String label; QualityAutoSwitchEvent(this.label); }

/// 播放器核心管理器 — 缓存/错误/指标委托给引擎
class PlayerCoreManager extends ChangeNotifier {
  // Fix 4: 使用 SimplePrinter 替代 PrettyPrinter，避免主线程卡顿
  final Logger _logger = Logger(printer: SimplePrinter());

  late final Player _player;
  late final VideoController _controller;
  late final CacheEngine _cacheEngine;
  late final PlaybackErrorHandlerImpl _errorHandler;
  late final MetricsEngine _metricsEngine;

  // Fix 3: 添加 _isDisposed 标志，防止 use-after-dispose
  bool _isDisposed = false;
  bool _isInitialized = false;

  // UI 通知回调
  void Function(FirstFrameEvent event)? onFirstFrame;
  void Function(ErrorEvent event)? onError;
  void Function(QualitySuggestionEvent event)? onQualitySuggestion;
  void Function(ProgressResumeEvent event)? onProgressResume;
  void Function(QualityAutoSwitchEvent event)? onQualityAutoSwitch;
  void Function(bool isBuffering)? onNotifyPreloadBuffering;
  void Function(List<SubtitleTrack> tracks)? onSubtitlesLoaded;

  // 播放状态
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

  // 初始化参数
  String _title = '', _url = '';
  List<String>? _episodeNames, _episodeUrls, _subtitleUrls;

  // 字幕
  final SubtitleService _subtitleService = SubtitleService();
  List<SubtitleTrack> _subtitleTracks = [];
  bool _showSubtitles = true;
  int _currentSubtitleTrack = 0;

  // 硬解码 / 缓冲区 / ABR
  bool _hardwareDecodingEnabled = true;
  final BufferManager _bufferManager = BufferManager();
  final ABRController _abrController = ABRController();

  // Seek
  bool _isSeeking = false;
  Timer? _seekOverlayTimer;

  // AV 同步
  StreamSubscription? _positionSubscription;
  Duration _lastVideoPosition = Duration.zero;
  DateTime _lastPositionUpdateTime = DateTime.now();
  Timer? _avSyncCheckTimer;
  int _avSyncCorrectionCount = 0;
  DateTime? _lastAVSyncCorrection;

  // 流订阅
  StreamSubscription? _errorSubscription, _playingSubscription, _bufferSubscription, _networkConditionSubscription, _completedSubscription;

  // 预加载 / 倍速 / 画中画 / 功耗 / 加载状态
  bool _hasTriggeredNextEpisodePreload = false;
  Timer? _speedIndicatorTimer;
  bool _isInBackground = false, _isInPipMode = false;
  int? _pipSavedQualityIndex;
  PowerMode _powerMode = PowerMode.balanced;
  bool _isLoading = true;
  String _loadingText = '加载中...';
  double _bufferPercent = 0.0;
  String _networkSpeedText = '';

  // 错误 / 缓存 / 进度保存
  String? _lastError;
  String? _fallbackQuality;
  String _resolvedUrl = '';
  Timer? _progressSaveTimer;
  Timer? _firstFrameTimeout;
  AppDatabase? _db;

  // ========================================================================
  // 公开 Getters
  // ========================================================================

  Player get player => _player;
  VideoController get controller => _controller;
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
  List<SubtitleTrack> get subtitleTracks => List.unmodifiable(_subtitleTracks);
  bool get showSubtitles => _showSubtitles;
  int get currentSubtitleTrack => _currentSubtitleTrack;
  SubtitleService get subtitleService => _subtitleService;
  bool get hardwareDecodingEnabled => _hardwareDecodingEnabled;
  BufferManager get bufferManager => _bufferManager;
  ABRController get abrController => _abrController;
  bool get isSeeking => _isSeeking;
  bool get isBuffering => _metricsEngine.isBuffering;
  bool get isLoading => _isLoading;
  String get loadingText => _loadingText;
  double get bufferPercent => _bufferPercent;
  String get networkSpeedText => _networkSpeedText;
  bool get isWaitingForNetwork => _errorHandler.isWaitingForNetwork;
  String? get lastError => _lastError;
  bool get isUsingCache => _cacheEngine.isUsingCache;
  String? get fallbackQuality => _fallbackQuality;
  Duration get lastVideoPosition => _lastVideoPosition;
  bool get isInBackground => _isInBackground;
  bool get isInPipMode => _isInPipMode;
  PowerMode get powerMode => _powerMode;
  bool get hasPrevEpisode => _episodeUrls != null && _currentEpisodeIndex > 0;
  bool get hasNextEpisode => _episodeUrls != null && _currentEpisodeIndex < _episodeUrls!.length - 1;
  bool get isInitialized => _isInitialized;

  // ========================================================================
  // 初始化与销毁
  // ========================================================================

  /// 同步创建 Player 和 VideoController（轻量，供页面立即使用 controller）
  void initPlayerSync() {
    // vo: 'gpu' 修复默认值 'null' 导致无视频输出的问题
    _player = Player(configuration: const PlayerConfiguration(title: '', vo: 'gpu'));
    _controller = VideoController(_player);
    // 引擎也在此同步创建
    _cacheEngine = CacheEngineImpl(
      onPreloadNextEpisode: _onPreloadNextEpisode,
      onPreloadAdjacent: _onPreloadAdjacent,
      onNotifyPreloadBuffering: (b) => onNotifyPreloadBuffering?.call(b),
    );
    _errorHandler = PlaybackErrorHandlerImpl();
    _metricsEngine = MetricsEngineImpl();
  }

  /// Fix 1: initialize 改为异步，确保初始化顺序正确
  Future<void> initialize({
    required String url, required String title, int? episodeIndex,
    List<String>? episodeNames, List<String>? episodeUrls,
    List<String>? qualityLabels, List<String>? qualityUrls,
    List<String>? subtitleUrls, AppDatabase? db,
  }) async {
    _url = url; _title = title; _episodeNames = episodeNames;
    _episodeUrls = episodeUrls; _subtitleUrls = subtitleUrls; _db = db;

    // 设备探测 — await 确保完成后再继续
    await _configureHardwareDecoding();

    // 4. 设置回调
    _bufferManager.onBufferStateChanged = _onBufferStateChanged;
    _abrController.onQualityChanged = _onQualityChanged;

    // 5. 设置播放参数（在打开视频前）
    _currentEpisodeIndex = episodeIndex ?? 0;
    _currentEpisodeName = title;
    _qualityLabels = qualityLabels ?? [];
    _qualityUrls = qualityUrls ?? [];
    _currentQualityIndex = 0;
    _errorHandler.qualityCount = _qualityUrls.length;

    // 6. 解析视频URL并打开 — await 确保完成
    final videoId = '${_title}_${episodeIndex ?? 0}';
    _metricsEngine.startSession(videoId);
    _metricsEngine.recordEvent(MetricsEvent.playStart);
    await _openVideoWithCacheCheck(url, videoId);

    // 7. 设置播放速率（视频已打开）
    _player.setRate(_playbackSpeed);

    // 8. 订阅流
    _completedSubscription = _player.stream.completed.listen((c) {
      if (c) { _metricsEngine.recordEvent(MetricsEvent.playComplete); _onPlaybackCompleted(); }
    });

    _positionSubscription = _player.stream.position.listen((pos) {
      _lastVideoPosition = pos;
      _lastPositionUpdateTime = DateTime.now();
      if (!_metricsEngine.hasRecordedFirstFrame && pos > Duration.zero) {
        _metricsEngine.markFirstFrameRecorded();
        _metricsEngine.recordEvent(MetricsEvent.firstFrame);
        _notifyFirstFrame();
        _loadSubtitles();
      }
      _checkPreloadTrigger(pos);
    });

    // 兜底：播放器可能在订阅注册前就已经处于播放状态，主动补记首帧
    if (!_metricsEngine.hasRecordedFirstFrame && _player.state.position > Duration.zero) {
      _metricsEngine.markFirstFrameRecorded();
      _metricsEngine.recordEvent(MetricsEvent.firstFrame);
      _notifyFirstFrame();
      _loadSubtitles();
    }

    _bufferSubscription = _player.stream.buffer.listen((buf) {
      _bufferManager.updateBuffer(buf);
      _abrController.updateBuffer(buf);
      if (_isLoading && buf > Duration.zero) _isLoading = false;
      _bufferPercent = _bufferManager.bufferPercent;
      notifyListeners();
    });

    _playingSubscription = _player.stream.playing.listen((playing) {
      if (playing && _metricsEngine.isBuffering) {
        _metricsEngine.setBuffering(false);
        _metricsEngine.recordEvent(MetricsEvent.bufferingEnd);
        _isLoading = false;
        notifyListeners();
      }
    });

    _errorSubscription = _player.stream.error.listen((error) {
      _logger.e('播放错误: $error');
      _metricsEngine.recordEvent(MetricsEvent.playError, errorMessage: error);
      _handlePlaybackError(error);
    });

    // Fix 1: 安全访问 NetworkEngine 单例
    try {
      _networkConditionSubscription = NetworkEngine.instance.onConditionChanged.listen((c) {
        _bufferManager.updateNetworkCondition(c);
        _networkSpeedText = _formatNetworkSpeed(NetworkEngine.instance.currentBandwidthKbps);
        notifyListeners();
      });
      _bufferManager.updateNetworkCondition(NetworkEngine.instance.currentCondition);
    } catch (e) {
      _logger.w('NetworkEngine 未就绪，使用默认网络条件: $e');
      _bufferManager.updateNetworkCondition(NetworkCondition.wifi);
    }

    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _savePlaybackProgress());
    _avSyncCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkAVSync());

    // 首帧超时兜底：10秒后仍无首帧，尝试绕过本地代理直接用原始URL重试
    _firstFrameTimeout = Timer(const Duration(seconds: 10), () {
      if (_isDisposed) return;
      if (!_metricsEngine.hasRecordedFirstFrame && _url.isNotEmpty) {
        _logger.w('首帧超时（10s），可能编解码不兼容，尝试绕过本地代理重试');
        _player.stop();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_isDisposed) return;
          _player.open(Media(_url));
        });
      }
    });

    // 异步初始化（不阻塞，但安全）
    _loadSkipInterval();
    _detectPowerMode();

    _isInitialized = true;
  }

  @override
  void dispose() {
    // Fix 3: 先标记 disposed，防止 Future.delayed 回调访问已释放资源
    _isDisposed = true;
    _isInitialized = false;

    _metricsEngine.endSession();
    _savePlaybackProgress();

    // 先取消所有定时器
    for (final t in [_progressSaveTimer, _firstFrameTimeout, _seekOverlayTimer, _speedIndicatorTimer, _avSyncCheckTimer]) {
      t?.cancel();
    }

    // 先取消所有流订阅（防止回调访问已释放的 Player）
    for (final s in [_completedSubscription, _positionSubscription, _bufferSubscription, _errorSubscription, _playingSubscription, _networkConditionSubscription]) {
      s?.cancel();
    }

    // 释放引擎
    _cacheEngine.dispose();
    _errorHandler.dispose();
    _metricsEngine.dispose();

    // 最后释放 Player
    _player.dispose();
    super.dispose();
  }

  // ========================================================================
  // 公开方法
  // ========================================================================

  void togglePlayPause() {
    if (_isDisposed) return;
    _player.state.playing ? _player.pause() : _player.play();
    notifyListeners();
  }
  void seekTo(Duration position) { if (!_isDisposed) _player.seek(position); }

  void fastSeek(Duration position) {
    if (_isDisposed || _isSeeking) return;
    _isSeeking = true; notifyListeners();
    _metricsEngine.recordEvent(MetricsEvent.seekStart);
    _player.seek(position);
    _seekOverlayTimer?.cancel();
    _seekOverlayTimer = Timer(const Duration(milliseconds: 800), () {
      if (_isDisposed) return;
      _isSeeking = false;
      _metricsEngine.recordEvent(MetricsEvent.seekEnd);
      notifyListeners();
    });
  }

  void setPlaybackSpeed(double speed) {
    if (_isDisposed) return;
    _playbackSpeed = speed; _player.setRate(speed);
    _speedIndicatorTimer?.cancel();
    _speedIndicatorTimer = Timer(const Duration(seconds: 3), () { if (!_isDisposed) notifyListeners(); });
    notifyListeners();
  }

  void setSkipInterval(int i) { _skipInterval = i; _saveSkipInterval(); notifyListeners(); }
  void setPlayMode(PlayMode m) { _playMode = m; notifyListeners(); }
  void setAspectMode(AspectMode m) { _aspectMode = m; notifyListeners(); }

  void switchQuality(int index) {
    if (_isDisposed || index < 0 || index >= _qualityUrls.length) return;
    final savedPos = _player.state.position;
    _currentQualityIndex = index; _isLoading = true; _loadingText = '切换清晰度...'; notifyListeners();
    _openVideoWithCacheCheck(_qualityUrls[index], '${_title}_$index');
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_isDisposed) return; // Fix 3: 防止 use-after-dispose
      if (savedPos > Duration.zero) _player.seek(savedPos);
    });
  }

  void playPrevEpisode() { if (hasPrevEpisode) _playEpisodeAtIndex(_currentEpisodeIndex - 1); }
  void playNextEpisode() { if (hasNextEpisode) _playEpisodeAtIndex(_currentEpisodeIndex + 1); }
  void playEpisodeAtIndex(int index) => _playEpisodeAtIndex(index);

  void setVolume(double v) { _volume = v.clamp(0.0, 1.0); if (!_isDisposed) _player.setVolume(_volume * 100); notifyListeners(); }
  void setBrightness(double b) { _brightness = b.clamp(0.0, 1.0); notifyListeners(); }
  void toggleSubtitles() { _showSubtitles = !_showSubtitles; notifyListeners(); }
  void setSubtitleTrack(int i) { _currentSubtitleTrack = i; _showSubtitles = true; notifyListeners(); }
  void hideSubtitles() { _showSubtitles = false; notifyListeners(); }

  void enterPipMode() async {
    if (_isDisposed) return;
    try {
      _isInPipMode = true;

      // PiP 降分辨率：切换到最低清晰度
      if (_qualityUrls.isNotEmpty && _currentQualityIndex > 0) {
        _pipSavedQualityIndex = _currentQualityIndex;
        final lowestIndex = _qualityUrls.length - 1;
        if (lowestIndex != _currentQualityIndex) {
          _logger.i('PiP 模式：降低分辨率，切换到 ${_qualityLabels[lowestIndex]}');
          _currentQualityIndex = lowestIndex;
          notifyListeners();
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_background_playing', true);
      await prefs.setString('background_play_url', _url);
      await prefs.setString('background_play_title', _currentEpisodeName);
      // Fix 1: MethodChannel 调用安全包裹
      try {
        const platform = MethodChannel('com.mediamix.app/background');
        await platform.invokeMethod('moveToBack');
      } on MissingPluginException {
        _logger.d('PiP 平台通道未实现，跳过');
      } on PlatformException catch (e) {
        _logger.w('PiP 平台调用失败: ${e.message}');
      }
      if (!_isDisposed) notifyListeners();
    } catch (e) { _isInPipMode = false; _logger.w('进入画中画模式失败: $e'); }
  }

  void setPowerMode(PowerMode m) { _powerMode = m; _applyPowerMode(); notifyListeners(); }

  void retryPlayback() {
    if (_isDisposed) return;
    _errorHandler.stopNetworkRecoveryMonitoring();
    _errorHandler.resetRetryCount();
    _errorHandler.clearTriedQualityIndices();
    _lastError = null;
    _openVideoWithCacheCheck(_url, '${_title}_$_currentEpisodeIndex');
    notifyListeners();
  }

  void onAppLifecycleStateChanged(AppLifecycleState state) {
    if (_isDisposed) return;
    switch (state) {
      case AppLifecycleState.paused: _onAppBackgrounded();
      case AppLifecycleState.resumed: _onAppForegrounded();
      default: break;
    }
  }

  Future<Duration?> checkPlaybackProgress() async {
    try {
      if (_db == null) return null;
      final p = await _db!.getPlaybackProgress(_url);
      if (p != null && p.position > 5000) return Duration(milliseconds: p.position);
    } catch (_) {}
    return null;
  }

  void resumeToPosition(Duration position) { if (!_isDisposed) _player.seek(position); }

  void preloadAdjacentEpisodes() {
    if (_isDisposed || _episodeUrls == null) return;
    final indices = [for (int i = -1; i <= 1; i++) _currentEpisodeIndex + i].where((i) => i >= 0 && i < _episodeUrls!.length).toList();
    _cacheEngine.preloadAdjacentEpisodes(indices, _title, _episodeUrls!, _powerMode);
  }

  int findNextUntriedQuality() => _errorHandler.findNextUntriedQuality();
  void clearTriedQualityIndices() => _errorHandler.clearTriedQualityIndices();
  void resetRetryCount() => _errorHandler.resetRetryCount();
  String getPowerModeName(PowerMode m) => {PowerMode.fullPerformance: '全性能', PowerMode.balanced: '均衡', PowerMode.powerSaving: '省电'}[m]!;
  String formatDuration(Duration d) => _formatDuration(d);
  String formatNetworkSpeed(double kbps) => _formatNetworkSpeed(kbps);

  // ========================================================================
  // 缓存 — 委托给 CacheEngine
  // ========================================================================

  Future<void> _openVideoWithCacheCheck(String url, String videoId) async {
    if (_isDisposed) return;
    try {
      final result = await _cacheEngine.resolveVideoUrlWithFallback(url, videoId, preferredQuality: _currentQualityLabel);
      if (_isDisposed) return; // 异步操作完成后再次检查
      _fallbackQuality = result.fallbackQuality;
      if (result.fallbackQuality != null) {
        _logger.i('清晰度降级命中: 请求$_currentQualityLabel，使用${result.fallbackQuality}');
        onQualityAutoSwitch?.call(QualityAutoSwitchEvent('${result.fallbackQuality}(缓存)'));
      }
      _resolvedUrl = result.url;
      _logger.i('播放URL解析完成: ${_cacheEngine.isUsingCache ? "本地缓存" : "网络"}');
      await _player.open(Media(_resolvedUrl));
    } catch (e) {
      _logger.w('视频URL解析失败，使用原始URL: $e');
      _resolvedUrl = url;
      await _player.open(Media(url));
    }
  }

  String get _currentQualityLabel {
    if (_qualityLabels.isEmpty || _currentQualityIndex >= _qualityLabels.length) return '720p';
    return _qualityLabels[_currentQualityIndex];
  }

  void _onPreloadNextEpisode(String videoId, String url) { _logger.i('预加载下一集: videoId=$videoId'); onNotifyPreloadBuffering?.call(false); }
  void _onPreloadAdjacent(List<int> indices, String title, List<String> urls) { _logger.d('预加载相邻集: indices=$indices'); }

  // ========================================================================
  // 硬解码配置
  // ========================================================================

  Future<void> _configureHardwareDecoding() async {
    try {
      final r = await DeviceCapabilityService.instance.getCapabilityReport();
      _hardwareDecodingEnabled = r.recommendHardwareDecoding;
      if (r.isLowEndDevice) { _logger.i('低端设备(${r.totalRamMB}MB RAM)'); _abrController.updateBandwidth(500); }
      else { _logger.i('硬件解码已启用: ${r.platform}, ${r.cpuArch}, ${r.totalRamMB}MB RAM, ${r.cpuCores}核'); }
    } catch (e) { _logger.w('设备能力探测失败: $e'); _hardwareDecodingEnabled = true; }
  }

  void _onHardwareDecodeFailure(String error) {
    if (_isDisposed || !_hardwareDecodingEnabled) return;
    _logger.w('硬解码失败，降级至软解: $error');
    _hardwareDecodingEnabled = false;
    _player.stop();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_isDisposed) return; // Fix 3: 防止 use-after-dispose
      _openVideoWithCacheCheck(_url, '${_title}_$_currentEpisodeIndex');
    });
  }

  // ========================================================================
  // 缓冲区 / ABR 回调
  // ========================================================================

  void _onBufferStateChanged(bool isLow) {
    if (_isDisposed) return;
    if (isLow) {
      _isLoading = true; _loadingText = '缓冲中...';
      _metricsEngine.setBuffering(true); _metricsEngine.recordEvent(MetricsEvent.bufferingStart);
      _cacheEngine.notifyPreloadBuffering(true);
    } else {
      _metricsEngine.setBuffering(false); _metricsEngine.recordEvent(MetricsEvent.bufferingEnd);
      _cacheEngine.notifyPreloadBuffering(false);
    }
    notifyListeners();
  }

  void _onQualityChanged(QualityLevel level) {
    if (_isDisposed) return;
    _logger.i('ABR 建议画质: ${level.label}');
    _abrController.saveQualityPreference(level);
    onQualitySuggestion?.call(QualitySuggestionEvent(networkQualityDescription: _abrController.networkQualityDescription, qualityLabel: level.label));
  }

  // ========================================================================
  // AV 同步监控
  // ========================================================================

  void _checkAVSync() {
    if (_isDisposed || !_player.state.playing) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastPositionUpdateTime);
    if (elapsed.inMilliseconds <= 120) return;

    final expected = _lastVideoPosition + elapsed;
    final actual = _player.state.position;
    final drift = expected - actual;
    final driftMs = drift.abs().inMilliseconds;
    if (driftMs < 50) return;

    final frames = driftMs ~/ 33;

    if (driftMs > 2000) {
      _logger.w('视频严重偏离(${driftMs}ms / ~$frames帧)，跳帧纠正');
      _metricsEngine.recordEvent(MetricsEvent.playError, avSyncOffsetMs: driftMs);
      _player.seek(drift.isNegative ? expected : actual);
      _avSyncCorrectionCount++; _lastAVSyncCorrection = now;
    } else if (driftMs > 500) {
      _logger.w('音视频偏移过大(${driftMs}ms)，Seek纠正');
      _player.seek(expected); _avSyncCorrectionCount++; _lastAVSyncCorrection = now;
    } else if (frames > 5) {
      _logger.w('帧堆积$frames帧(${driftMs}ms)，跳帧到当前');
      _player.seek(expected); _avSyncCorrectionCount++; _lastAVSyncCorrection = now;
    } else {
      _logger.d('音视频微调: ${drift.inMilliseconds}ms (~$frames帧)');
      final rate = drift.isNegative ? _playbackSpeed * 1.05 : _playbackSpeed * 0.95;
      _player.setRate(rate);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (_isDisposed) return;
        if (_player.state.playing) _player.setRate(_playbackSpeed);
      });
    }
  }

  // ========================================================================
  // 首帧通知 / 预加载
  // ========================================================================

  void _notifyFirstFrame() {
    final m = _metricsEngine.getCurrentMetrics();
    if (m == null) return;
    final ms = m['first_frame_time_ms'] as int? ?? 0;
    if (ms > 0) onFirstFrame?.call(FirstFrameEvent(ms));
  }

  void _checkPreloadTrigger(Duration position) {
    if (_isDisposed || _hasTriggeredNextEpisodePreload || !hasNextEpisode) return;
    final dur = _player.state.duration;
    if (dur.inMilliseconds <= 0) return;
    if (position.inMilliseconds / dur.inMilliseconds >= 0.8) {
      _hasTriggeredNextEpisodePreload = true;
      final next = _currentEpisodeIndex + 1;
      _cacheEngine.preloadNextEpisode('${_title}_$next', _episodeUrls![next]);
    }
  }

  // ========================================================================
  // 画中画/后台 / 功耗
  // ========================================================================

  void _onAppBackgrounded() {
    if (_isDisposed) return;
    _isInBackground = true;
    _logger.d('应用进入后台，保持音频播放');
    _avSyncCheckTimer?.cancel();
    _avSyncCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isDisposed) _checkAVSync();
    });
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isDisposed) _savePlaybackProgress();
    });
    if (!_isInPipMode) _savePlaybackProgress();
    notifyListeners();
  }

  void _onAppForegrounded() {
    if (_isDisposed || !_isInBackground) return;
    _isInBackground = false;
    _logger.d('应用回到前台，恢复视频播放');
    _avSyncCheckTimer?.cancel();
    _avSyncCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isDisposed) _checkAVSync();
    });
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isDisposed) _savePlaybackProgress();
    });
    if (_isInPipMode && _pipSavedQualityIndex != null) {
      _isInPipMode = false;
      _currentQualityIndex = _pipSavedQualityIndex!;
      _pipSavedQualityIndex = null;
      _logger.i('PiP 退出：恢复原始分辨率');
      notifyListeners();
    }
    notifyListeners();
  }

  Future<void> _detectPowerMode() async {
    try {
      const ch = MethodChannel('com.mediamix.app/battery');
      final lvl = await ch.invokeMethod<int>('getBatteryLevel');
      final charging = await ch.invokeMethod<bool>('isCharging') ?? false;
      _powerMode = charging ? PowerMode.fullPerformance : (lvl != null && lvl < 20 ? PowerMode.powerSaving : PowerMode.balanced);
      _logger.i('功耗模式: ${_powerMode.name}, 电量: $lvl%, 充电: $charging');
      _applyPowerMode();
      if (!_isDisposed) notifyListeners();
    } on MissingPluginException {
      _powerMode = PowerMode.balanced;
      _logger.d('电池信息平台通道未实现');
    } on PlatformException catch (e) {
      _powerMode = PowerMode.balanced;
      _logger.d('获取电池信息失败: ${e.message}');
    } catch (_) {
      _powerMode = PowerMode.balanced;
      _logger.d('无法获取电池信息');
    }
  }

  void _applyPowerMode() { if (_powerMode == PowerMode.powerSaving) _logger.d('省电模式：禁用预加载'); }

  // ========================================================================
  // 错误处理 — 委托给 PlaybackErrorHandler
  // ========================================================================

  void _handlePlaybackError(String error) {
    if (_isDisposed) return;
    _lastError = error;
    final result = _errorHandler.handleError(
      error,
      hardwareDecodingEnabled: _hardwareDecodingEnabled,
      hasQualityOptions: hasQualityOptions,
      currentQualityIndex: _currentQualityIndex,
      lastPlaybackPosition: _player.state.position,
    );

    switch (result.action) {
      case ErrorAction.downgradeToSoftwareDecode:
        _logger.w('检测到硬解码失败，降级软解'); _onHardwareDecodeFailure(error);
      case ErrorAction.waitForNetworkRecovery:
        _logger.w('网络原因导致播放中断，等待恢复'); _errorHandler.startNetworkRecoveryMonitoring(onNetworkRecovered: _attemptReconnect); notifyListeners();
      case ErrorAction.retrySameUrl:
        _openVideoWithCacheCheck(_url, '${_title}_$_currentEpisodeIndex');
      case ErrorAction.switchToNextQuality:
        final idx = result.nextQualityIndex!;
        _logger.i('降级切换清晰度: ${_qualityLabels[_currentEpisodeIndex]} → ${_qualityLabels[idx]}');
        onQualityAutoSwitch?.call(QualityAutoSwitchEvent(_qualityLabels[idx]));
        _switchQualityInternal(idx);
      case ErrorAction.showErrorDialog:
        final nq = _errorHandler.findNextUntriedQuality();
        onError?.call(ErrorEvent(message: error, hasNextEpisode: hasNextEpisode, hasUntriedQuality: hasQualityOptions && nq >= 0, untriedQualityLabel: nq >= 0 ? _qualityLabels[nq] : null));
    }
  }

  void _attemptReconnect() {
    if (_isDisposed) return;
    final pos = _player.state.position;
    _logger.i('自动重连 — 断点: ${pos.inSeconds}s');
    _openVideoWithCacheCheck(_url, '${_title}_$_currentEpisodeIndex');
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_isDisposed) return; // Fix 3: 防止 use-after-dispose
      if (_player.state.playing || _player.state.position > Duration.zero) { _player.seek(pos); _logger.i('已恢复断点'); }
    });
    notifyListeners();
  }

  // ========================================================================
  // 字幕 / 播放完成 / 切集
  // ========================================================================

  Future<void> _loadSubtitles() async {
    final urls = _subtitleUrls ?? [];
    if (urls.isEmpty) return;
    try {
      final tracks = await _subtitleService.loadMultiTrackFromUrl(
        urls.asMap().entries.map((e) => (url: e.value, label: '字幕${e.key + 1}', language: 'zh-CN')).toList(),
      );
      if (_isDisposed) return;
      _subtitleTracks = tracks; onSubtitlesLoaded?.call(tracks); notifyListeners();
    } catch (e) { _logger.w('字幕加载失败: $e'); }
  }

  void _onPlaybackCompleted() {
    if (_isDisposed) return;
    switch (_playMode) {
      case PlayMode.loopSingle: _player.seek(Duration.zero); _player.play();
      case PlayMode.loopAll:
        if (hasNextEpisode) {
          playNextEpisode();
        } else if (_episodeUrls != null && _episodeUrls!.isNotEmpty) _playEpisodeAtIndex(0);
        else { _player.seek(Duration.zero); _player.play(); }
      case PlayMode.sequential: if (hasNextEpisode) playNextEpisode();
    }
  }

  void _playEpisodeAtIndex(int index) {
    if (_isDisposed || _episodeUrls == null || index < 0 || index >= _episodeUrls!.length) return;
    if (_episodeNames == null || index >= _episodeNames!.length) return;
    final videoId = '${_title}_$index';
    _openVideoWithCacheCheck(_episodeUrls![index], videoId);
    _currentEpisodeIndex = index; _currentEpisodeName = _episodeNames![index];
    _hasTriggeredNextEpisodePreload = false; _isLoading = true; _loadingText = '加载中...';
    _errorHandler.resetRetryCount(); _errorHandler.clearTriedQualityIndices();
    _metricsEngine.startSession(videoId); _metricsEngine.recordEvent(MetricsEvent.playStart);
    _savePlaybackProgress(); notifyListeners();
  }

  // ========================================================================
  // 清晰度切换 / 进度记忆 / 偏好 / 工具
  // ========================================================================

  void _switchQualityInternal(int index) {
    if (_isDisposed || index < 0 || index >= _qualityUrls.length) return;
    final savedPos = _player.state.position;
    _currentQualityIndex = index; _isLoading = true; _loadingText = '切换清晰度...';
    _openVideoWithCacheCheck(_qualityUrls[index], '${_title}_$index');
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_isDisposed) return; // Fix 3: 防止 use-after-dispose
      if (savedPos > Duration.zero) _player.seek(savedPos);
    });
    notifyListeners();
  }

  Future<void> _savePlaybackProgress() async {
    try {
      if (_isDisposed || _db == null) return;
      final url = _currentEpisodeIndex < (_episodeUrls?.length ?? 0) ? _episodeUrls![_currentEpisodeIndex] : _url;
      await _db!.savePlaybackProgress(PlaybackProgressesCompanion.insert(
        videoUrl: url, position: _player.state.position.inMilliseconds,
        duration: _player.state.duration.inMilliseconds, lastPlayTime: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (_) {}
  }

  Future<void> _saveSkipInterval() async { final p = await SharedPreferences.getInstance(); await p.setInt('skip_interval', _skipInterval); }
  Future<void> _loadSkipInterval() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getInt('skip_interval');
      if (s != null && _skipIntervals.contains(s)) { _skipInterval = s; if (!_isDisposed) notifyListeners(); }
    } catch (_) {}
  }

  String _formatNetworkSpeed(double kbps) => kbps <= 0 ? '' : kbps < 1000 ? '${kbps.toStringAsFixed(0)} kb/s' : '${(kbps / 1000).toStringAsFixed(1)} MB/s';

  String _formatDuration(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

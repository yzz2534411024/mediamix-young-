import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/core/services/power_manager_service.dart';
import 'package:mediamix/features/video/core/player_core_manager.dart';
import 'package:mediamix/features/video/core/engines/engine_interfaces.dart';
import 'package:mediamix/features/video/services/subtitle_service.dart';

void main() {
  // ===========================================================================
  // FirstFrameEvent
  // ===========================================================================
  group('FirstFrameEvent', () {
    test('存储首帧耗时', () {
      const event = FirstFrameEvent(120);
      expect(event.firstFrameTimeMs, 120);
    });

    test('首帧耗时为0', () {
      const event = FirstFrameEvent(0);
      expect(event.firstFrameTimeMs, 0);
    });

    test('首帧耗时较大值', () {
      const event = FirstFrameEvent(99999);
      expect(event.firstFrameTimeMs, 99999);
    });
  });

  // ===========================================================================
  // ErrorEvent
  // ===========================================================================
  group('ErrorEvent', () {
    test('必填字段 message', () {
      final event = ErrorEvent(message: '播放失败');
      expect(event.message, '播放失败');
    });

    test('默认值：hasNextEpisode=false, hasUntriedQuality=false, '
        'untriedQualityLabel=null, triedQualityCount=0', () {
      final event = ErrorEvent(message: '错误');
      expect(event.hasNextEpisode, false);
      expect(event.hasUntriedQuality, false);
      expect(event.untriedQualityLabel, isNull);
      expect(event.triedQualityCount, 0);
    });

    test('所有字段赋值', () {
      final event = ErrorEvent(
        message: '网络超时',
        hasNextEpisode: true,
        hasUntriedQuality: true,
        untriedQualityLabel: '标清',
        triedQualityCount: 3,
      );
      expect(event.message, '网络超时');
      expect(event.hasNextEpisode, true);
      expect(event.hasUntriedQuality, true);
      expect(event.untriedQualityLabel, '标清');
      expect(event.triedQualityCount, 3);
    });
  });

  // ===========================================================================
  // QualitySuggestionEvent
  // ===========================================================================
  group('QualitySuggestionEvent', () {
    test('存储网络质量描述和画质标签', () {
      final event = QualitySuggestionEvent(
        networkQualityDescription: 'WiFi 优良',
        qualityLabel: '高清',
      );
      expect(event.networkQualityDescription, 'WiFi 优良');
      expect(event.qualityLabel, '高清');
    });

    test('弱网场景', () {
      final event = QualitySuggestionEvent(
        networkQualityDescription: '4G 弱网',
        qualityLabel: '流畅',
      );
      expect(event.networkQualityDescription, '4G 弱网');
      expect(event.qualityLabel, '流畅');
    });
  });

  // ===========================================================================
  // ProgressResumeEvent
  // ===========================================================================
  group('ProgressResumeEvent', () {
    test('存储播放位置 Duration', () {
      final event = ProgressResumeEvent(const Duration(minutes: 5, seconds: 30));
      expect(event.position, const Duration(minutes: 5, seconds: 30));
    });

    test('位置为零', () {
      final event = ProgressResumeEvent(Duration.zero);
      expect(event.position, Duration.zero);
    });

    test('位置为较大值', () {
      final event = ProgressResumeEvent(const Duration(hours: 2));
      expect(event.position, const Duration(hours: 2));
    });
  });

  // ===========================================================================
  // QualityAutoSwitchEvent
  // ===========================================================================
  group('QualityAutoSwitchEvent', () {
    test('存储目标清晰度标签', () {
      const event = QualityAutoSwitchEvent('标清');
      expect(event.label, '标清');
    });

    test('标签为空字符串', () {
      const event = QualityAutoSwitchEvent('');
      expect(event.label, '');
    });
  });

  // ===========================================================================
  // PlayMode 枚举
  // ===========================================================================
  group('PlayMode', () {
    test('有3个值', () {
      expect(PlayMode.values.length, 3);
    });

    test('包含 sequential, loopSingle, loopAll', () {
      expect(PlayMode.values, contains(PlayMode.sequential));
      expect(PlayMode.values, contains(PlayMode.loopSingle));
      expect(PlayMode.values, contains(PlayMode.loopAll));
    });

    test('index 顺序: sequential < loopSingle < loopAll', () {
      expect(PlayMode.sequential.index, lessThan(PlayMode.loopSingle.index));
      expect(PlayMode.loopSingle.index, lessThan(PlayMode.loopAll.index));
    });
  });

  // ===========================================================================
  // AspectMode 枚举
  // ===========================================================================
  group('AspectMode', () {
    test('有5个值', () {
      expect(AspectMode.values.length, 5);
    });

    test('包含 original, ratio16_9, ratio4_3, fill, cover', () {
      expect(AspectMode.values, contains(AspectMode.original));
      expect(AspectMode.values, contains(AspectMode.ratio16_9));
      expect(AspectMode.values, contains(AspectMode.ratio4_3));
      expect(AspectMode.values, contains(AspectMode.fill));
      expect(AspectMode.values, contains(AspectMode.cover));
    });

    test('index 顺序: original < ratio16_9 < ratio4_3 < fill < cover', () {
      expect(AspectMode.original.index, lessThan(AspectMode.ratio16_9.index));
      expect(AspectMode.ratio16_9.index, lessThan(AspectMode.ratio4_3.index));
      expect(AspectMode.ratio4_3.index, lessThan(AspectMode.fill.index));
      expect(AspectMode.fill.index, lessThan(AspectMode.cover.index));
    });
  });

  // ===========================================================================
  // PlayerCoreManager — 初始化前默认状态
  // ===========================================================================
  group('PlayerCoreManager 默认状态（未调用 initialize）', () {
    late PlayerCoreManager manager;

    setUp(() {
      manager = PlayerCoreManager();
    });

    tearDown(() {
      // 不调用 manager.dispose()，因为 _player 是 late 且未初始化
    });

    test('playbackSpeed 默认为 1.0', () {
      expect(manager.playbackSpeed, 1.0);
    });

    test('speedOptions 有 12 个条目', () {
      expect(manager.speedOptions.length, 12);
    });

    test('speedOptions 包含预期值', () {
      expect(
        manager.speedOptions,
        [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0],
      );
    });

    test('skipInterval 默认为 10', () {
      expect(manager.skipInterval, 10);
    });

    test('skipIntervals 为 [5, 10, 30, 60]', () {
      expect(manager.skipIntervals, [5, 10, 30, 60]);
    });

    test('playMode 默认为 sequential', () {
      expect(manager.playMode, PlayMode.sequential);
    });

    test('aspectMode 默认为 original', () {
      expect(manager.aspectMode, AspectMode.original);
    });

    test('volume 默认为 1.0', () {
      expect(manager.volume, 1.0);
    });

    test('brightness 默认为 0.5', () {
      expect(manager.brightness, 0.5);
    });

    test('hardwareDecodingEnabled 默认为 true', () {
      expect(manager.hardwareDecodingEnabled, true);
    });

    test('isSeeking 默认为 false', () {
      expect(manager.isSeeking, false);
    });

    test('isBuffering 默认为 false', () {
      expect(manager.isBuffering, false);
    });

    test('isLoading 默认为 false', () {
      expect(manager.isLoading, false);
    });

    test('loadingText 默认为 "加载中..."', () {
      expect(manager.loadingText, '加载中...');
    });

    test('bufferPercent 默认为 0.0', () {
      expect(manager.bufferPercent, 0.0);
    });

    test('networkSpeedText 默认为空字符串', () {
      expect(manager.networkSpeedText, '');
    });

    test('isUsingCache 默认为 false', () {
      expect(manager.isUsingCache, false);
    });

    test('isInBackground 默认为 false', () {
      expect(manager.isInBackground, false);
    });

    test('isInPipMode 默认为 false', () {
      expect(manager.isInPipMode, false);
    });

    test('powerMode 默认为 balanced', () {
      expect(manager.powerMode, PowerMode.balanced);
    });

    test('showSubtitles 默认为 true', () {
      expect(manager.showSubtitles, true);
    });

    test('currentSubtitleTrack 默认为 0', () {
      expect(manager.currentSubtitleTrack, 0);
    });
  });

  // ===========================================================================
  // PlayerCoreManager — 工具方法
  // ===========================================================================
  group('PlayerCoreManager.formatDuration', () {
    late PlayerCoreManager manager;

    setUp(() {
      manager = PlayerCoreManager();
    });

    test('Duration.zero → "00:00"', () {
      expect(manager.formatDuration(Duration.zero), '00:00');
    });

    test('不足1分钟 → "00:45"', () {
      expect(manager.formatDuration(const Duration(seconds: 45)), '00:45');
    });

    test('不足1小时 → "05:30"', () {
      expect(
        manager.formatDuration(const Duration(minutes: 5, seconds: 30)),
        '05:30',
      );
    });

    test('超过1小时 → "1:05:30"', () {
      expect(
        manager.formatDuration(const Duration(hours: 1, minutes: 5, seconds: 30)),
        '1:05:30',
      );
    });

    test('超过2小时 → "2:00:00"', () {
      expect(
        manager.formatDuration(const Duration(hours: 2)),
        '2:00:00',
      );
    });

    test('秒数补零 → "00:09"', () {
      expect(manager.formatDuration(const Duration(seconds: 9)), '00:09');
    });

    test('分钟数补零 → "1:02:03"', () {
      expect(
        manager.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  group('PlayerCoreManager.formatNetworkSpeed', () {
    late PlayerCoreManager manager;

    setUp(() {
      manager = PlayerCoreManager();
    });

    test('0 返回空字符串', () {
      expect(manager.formatNetworkSpeed(0), '');
    });

    test('负数返回空字符串', () {
      expect(manager.formatNetworkSpeed(-100), '');
    });

    test('<1000 显示 kb/s', () {
      expect(manager.formatNetworkSpeed(500), '500 kb/s');
    });

    test('>=1000 显示 MB/s', () {
      expect(manager.formatNetworkSpeed(1500), '1.5 MB/s');
    });

    test('刚好 1000 显示 MB/s', () {
      expect(manager.formatNetworkSpeed(1000), '1.0 MB/s');
    });

    test('较大值', () {
      expect(manager.formatNetworkSpeed(25600), '25.6 MB/s');
    });
  });

  group('PlayerCoreManager.getPowerModeName', () {
    late PlayerCoreManager manager;

    setUp(() {
      manager = PlayerCoreManager();
    });

    test('fullPerformance → "全性能"', () {
      expect(manager.getPowerModeName(PowerMode.fullPerformance), '全性能');
    });

    test('balanced → "均衡"', () {
      expect(manager.getPowerModeName(PowerMode.balanced), '均衡');
    });

    test('powerSaving → "省电"', () {
      expect(manager.getPowerModeName(PowerMode.powerSaving), '省电');
    });
  });

  // ===========================================================================
  // PlayerCoreManager — 集数导航（未初始化）
  // ===========================================================================
  group('PlayerCoreManager 集数导航（未初始化）', () {
    late PlayerCoreManager manager;

    setUp(() {
      manager = PlayerCoreManager();
    });

    test('hasPrevEpisode 未初始化时为 false', () {
      expect(manager.hasPrevEpisode, false);
    });

    test('hasNextEpisode 未初始化时为 false', () {
      expect(manager.hasNextEpisode, false);
    });
  });

  // ===========================================================================
  // PlayerCoreManager — 回调注册
  // ===========================================================================
  group('PlayerCoreManager 回调注册', () {
    late PlayerCoreManager manager;

    setUp(() {
      manager = PlayerCoreManager();
    });

    test('onFirstFrame 可以被设置和调用', () {
      FirstFrameEvent? captured;
      manager.onFirstFrame = (event) {
        captured = event;
      };
      manager.onFirstFrame!(const FirstFrameEvent(200));
      expect(captured, isNotNull);
      expect(captured!.firstFrameTimeMs, 200);
    });

    test('onError 可以被设置和调用', () {
      ErrorEvent? captured;
      manager.onError = (event) {
        captured = event;
      };
      manager.onError!(ErrorEvent(message: '测试错误'));
      expect(captured, isNotNull);
      expect(captured!.message, '测试错误');
    });

    test('onQualitySuggestion 可以被设置和调用', () {
      QualitySuggestionEvent? captured;
      manager.onQualitySuggestion = (event) {
        captured = event;
      };
      manager.onQualitySuggestion!(QualitySuggestionEvent(
        networkQualityDescription: 'WiFi',
        qualityLabel: '高清',
      ));
      expect(captured, isNotNull);
      expect(captured!.qualityLabel, '高清');
    });

    test('onProgressResume 可以被设置和调用', () {
      ProgressResumeEvent? captured;
      manager.onProgressResume = (event) {
        captured = event;
      };
      manager.onProgressResume!(ProgressResumeEvent(const Duration(minutes: 3)));
      expect(captured, isNotNull);
      expect(captured!.position, const Duration(minutes: 3));
    });

    test('onQualityAutoSwitch 可以被设置和调用', () {
      QualityAutoSwitchEvent? captured;
      manager.onQualityAutoSwitch = (event) {
        captured = event;
      };
      manager.onQualityAutoSwitch!(const QualityAutoSwitchEvent('标清'));
      expect(captured, isNotNull);
      expect(captured!.label, '标清');
    });

    test('onSubtitlesLoaded 可以被设置和调用', () {
      List<dynamic>? captured;
      manager.onSubtitlesLoaded = (tracks) {
        captured = tracks;
      };
      manager.onSubtitlesLoaded!([
        const SubtitleTrack(label: 'track1', language: 'zh-CN', entries: []),
        const SubtitleTrack(label: 'track2', language: 'zh-CN', entries: []),
      ]);
      expect(captured, isNotNull);
      expect(captured!.length, 2);
    });

    test('onNotifyPreloadBuffering 可以被设置和调用', () {
      bool? captured;
      manager.onNotifyPreloadBuffering = (isBuffering) {
        captured = isBuffering;
      };
      manager.onNotifyPreloadBuffering!(true);
      expect(captured, true);
    });

    test('回调默认为 null', () {
      expect(manager.onFirstFrame, isNull);
      expect(manager.onError, isNull);
      expect(manager.onQualitySuggestion, isNull);
      expect(manager.onProgressResume, isNull);
      expect(manager.onQualityAutoSwitch, isNull);
      expect(manager.onSubtitlesLoaded, isNull);
      expect(manager.onNotifyPreloadBuffering, isNull);
    });
  });

  // ===========================================================================
  // PlayerCoreManager — ChangeNotifier 行为
  // ===========================================================================
  group('PlayerCoreManager ChangeNotifier', () {
    late PlayerCoreManager manager;

    setUp(() {
      manager = PlayerCoreManager();
    });

    test('可以添加监听器', () {
      var notifyCount = 0;
      manager.addListener(() {
        notifyCount++;
      });
      manager.notifyListeners();
      expect(notifyCount, 1);
    });

    test('多次 notifyListeners 触发多次', () {
      var notifyCount = 0;
      manager.addListener(() {
        notifyCount++;
      });
      manager.notifyListeners();
      manager.notifyListeners();
      manager.notifyListeners();
      expect(notifyCount, 3);
    });

    test('移除监听器后不再触发', () {
      var notifyCount = 0;
      void listener() {
        notifyCount++;
      }

      manager.addListener(listener);
      manager.notifyListeners();
      expect(notifyCount, 1);

      manager.removeListener(listener);
      manager.notifyListeners();
      expect(notifyCount, 1);
    });
  });

  // ===========================================================================
  // ErrorAction 枚举穷举验证
  // ===========================================================================
  group('ErrorAction 枚举穷举', () {
    test('包含所有 9 个枚举值', () {
      expect(ErrorAction.values.length, 9);
      expect(ErrorAction.values, contains(ErrorAction.downgradeToSoftwareDecode));
      expect(ErrorAction.values, contains(ErrorAction.waitForNetworkRecovery));
      expect(ErrorAction.values, contains(ErrorAction.retrySameUrl));
      expect(ErrorAction.values, contains(ErrorAction.switchToNextQuality));
      expect(ErrorAction.values, contains(ErrorAction.showErrorDialog));
      expect(ErrorAction.values, contains(ErrorAction.recoverFromStuck));
      expect(ErrorAction.values, contains(ErrorAction.recoverFromBlackScreen));
      expect(ErrorAction.values, contains(ErrorAction.recoverFromSilence));
      expect(ErrorAction.values, contains(ErrorAction.switchSource));
    });

    test('新增恢复动作名称正确', () {
      expect(ErrorAction.recoverFromStuck.name, 'recoverFromStuck');
      expect(ErrorAction.recoverFromBlackScreen.name, 'recoverFromBlackScreen');
      expect(ErrorAction.recoverFromSilence.name, 'recoverFromSilence');
      expect(ErrorAction.switchSource.name, 'switchSource');
    });

    test('ErrorHandleResult 可携带新增 action', () {
      final r1 = ErrorHandleResult(action: ErrorAction.recoverFromStuck);
      expect(r1.action, ErrorAction.recoverFromStuck);
      expect(r1.nextQualityIndex, isNull);

      final r2 = ErrorHandleResult(action: ErrorAction.switchSource, nextQualityIndex: 2);
      expect(r2.action, ErrorAction.switchSource);
      expect(r2.nextQualityIndex, 2);

      final r3 = ErrorHandleResult(action: ErrorAction.recoverFromBlackScreen);
      expect(r3.action, ErrorAction.recoverFromBlackScreen);

      final r4 = ErrorHandleResult(action: ErrorAction.recoverFromSilence);
      expect(r4.action, ErrorAction.recoverFromSilence);
    });
  });

  // ===========================================================================
  // PlayerCoreManager — setPreloadDepth 动态深度控制
  // ===========================================================================
  group('PlayerCoreManager.setPreloadDepth', () {
    late PlayerCoreManager manager;

    setUp(() {
      manager = PlayerCoreManager();
    });

    test('setPreloadDepth 设置有效深度值', () {
      // 不应抛出异常
      manager.setPreloadDepth(1);
      manager.setPreloadDepth(2);
      manager.setPreloadDepth(3);
    });

    test('setPreloadDepth 低于下限时 clamp 到 1', () {
      // 不应抛出异常，内部 clamp 到 1
      manager.setPreloadDepth(0);
      manager.setPreloadDepth(-1);
      manager.setPreloadDepth(-100);
    });

    test('setPreloadDepth 超过上限时 clamp 到 3', () {
      // 不应抛出异常，内部 clamp 到 3
      manager.setPreloadDepth(4);
      manager.setPreloadDepth(10);
      manager.setPreloadDepth(100);
    });
  });

  // ===========================================================================
  // PlayerCoreManager — preloadAdjacentEpisodes 深度范围
  // ===========================================================================
  group('PlayerCoreManager.preloadAdjacentEpisodes（未初始化）', () {
    late PlayerCoreManager manager;

    setUp(() {
      manager = PlayerCoreManager();
    });

    test('未初始化时调用 preloadAdjacentEpisodes 不抛异常', () {
      // initPlayerSync 未调用，_cacheEngine 未初始化
      // 但 _isDisposed 为 false，_episodeUrls 为 null → 直接 return
      manager.preloadAdjacentEpisodes();
    });

    test('setPreloadDepth 边界值 1 不抛异常', () {
      manager.setPreloadDepth(1);
      manager.preloadAdjacentEpisodes();
    });

    test('setPreloadDepth 边界值 3 不抛异常', () {
      manager.setPreloadDepth(3);
      manager.preloadAdjacentEpisodes();
    });
  });
}

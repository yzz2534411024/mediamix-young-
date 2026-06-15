// 注意：修改此文件后需要运行以下命令重新生成 database.g.dart：
// flutter pub run build_runner build

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'database.g.dart';

/// 视频接口源表
class VideoSources extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  TextColumn get type => text().withDefault(const Constant('tbox'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get lastUpdateTime => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 播放进度表
@DataClassName('PlaybackProgress')
class PlaybackProgresses extends Table {
  TextColumn get videoUrl => text()();
  IntColumn get position => integer()(); // 毫秒
  IntColumn get duration => integer()(); // 毫秒
  IntColumn get lastPlayTime => integer()(); // 最后播放时间戳

  @override
  Set<Column> get primaryKey => {videoUrl};
}

/// 观看历史表
@DataClassName('WatchHistory')
class WatchHistories extends Table {
  TextColumn get vodId => text()();
  TextColumn get vodName => text()();
  TextColumn get vodPic => text().nullable()();
  TextColumn get sourceKey => text()();
  TextColumn get episodeName => text().nullable()();
  IntColumn get lastWatchTime => integer()();

  @override
  Set<Column> get primaryKey => {vodId};
}

/// 收藏表
@DataClassName('Favorite')
class Favorites extends Table {
  TextColumn get vodId => text()();
  TextColumn get vodName => text()();
  TextColumn get vodPic => text().nullable()();
  TextColumn get sourceKey => text()();
  TextColumn get typeName => text().nullable()();
  IntColumn get lastEpisodeCount => integer().withDefault(const Constant(0))(); // 追踪集数
  IntColumn get addTime => integer()(); // 收藏时间戳

  @override
  Set<Column> get primaryKey => {vodId};
}

/// 下载任务表
@DataClassName('DownloadTask')
class DownloadTasks extends Table {
  TextColumn get id => text()();
  TextColumn get vodId => text()();
  TextColumn get vodName => text()();
  TextColumn get episodeName => text()();
  TextColumn get videoUrl => text()();
  TextColumn get localPath => text().withDefault(const Constant(''))();
  IntColumn get status => integer().withDefault(const Constant(0))(); // 0=等待, 1=下载中, 2=已完成, 3=失败
  IntColumn get progress => integer().withDefault(const Constant(0))(); // 0~100
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  IntColumn get createTime => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 性能指标事件表 — 原始埋点事件持久化
@DataClassName('MetricsEventRecord')
class MetricsEvents extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get sessionId => text()();
  TextColumn get videoId => text()();
  TextColumn get eventType => text()(); // MetricsEvent 枚举名
  IntColumn get timestamp => integer()(); // 事件时间戳（毫秒）
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))(); // 附加数据 JSON
  BoolColumn get uploaded => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 性能指标会话表 — 播放会话汇总数据
@DataClassName('MetricsSession')
class MetricsSessions extends Table {
  TextColumn get sessionId => text()();
  TextColumn get videoId => text()();
  IntColumn get firstFrameTimeMs => integer().withDefault(const Constant(0))();
  IntColumn get bufferingCount => integer().withDefault(const Constant(0))();
  IntColumn get bufferingTotalMs => integer().withDefault(const Constant(0))();
  RealColumn get stutterRate => real().withDefault(const Constant(0.0))();
  IntColumn get qualityChanges => integer().withDefault(const Constant(0))();
  IntColumn get seekCount => integer().withDefault(const Constant(0))();
  IntColumn get seekAvgMs => integer().withDefault(const Constant(0))();
  IntColumn get errorCount => integer().withDefault(const Constant(0))();
  IntColumn get cacheHits => integer().withDefault(const Constant(0))();
  IntColumn get cacheMisses => integer().withDefault(const Constant(0))();
  RealColumn get avgBandwidthKbps => real().withDefault(const Constant(0.0))();
  RealColumn get peakBandwidthKbps => real().withDefault(const Constant(0.0))();
  IntColumn get startTime => integer()(); // 会话开始时间戳
  IntColumn get endTime => integer().nullable()(); // 会话结束时间戳
  BoolColumn get uploaded => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {sessionId};
}

@DriftDatabase(tables: [VideoSources, PlaybackProgresses, WatchHistories, Favorites, DownloadTasks, MetricsEvents, MetricsSessions])
class AppDatabase extends _$AppDatabase {
  static AppDatabase? _instance;
  static AppDatabase get instance => _instance ??= AppDatabase._();

  AppDatabase._() : super(_openConnection());

  /// 保留公开构造以兼容 build_runner，但推荐使用 [instance]
  factory AppDatabase() => instance;

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (Migrator m, int from, int to) async {
      _log('数据库迁移: $from -> $to');
      if (from < 2) {
        await m.deleteTable('video_sources');
        await m.createAll();
      }
      if (from < 3) {
        await m.createTable(playbackProgresses);
      }
      if (from < 4) {
        await m.createTable(watchHistories);
      }
      if (from < 5) {
        await m.createTable(favorites);
      }
      if (from < 6) {
        await m.createTable(downloadTasks);
      }
      if (from < 7) {
        await m.createTable(metricsEvents);
        await m.createTable(metricsSessions);
      }
    },
    onCreate: (Migrator m) async {
      _log('创建数据库');
      await m.createAll();
    },
  );

  void _log(String msg) {
    // 简单日志，生产环境可替换为 logger
    // ignore: avoid_print
    print('[DB] $msg');
  }

  // ===== 视频源 CRUD =====

  Future<List<VideoSource>> getAllVideoSources() => select(videoSources).get();

  Stream<List<VideoSource>> watchAllVideoSources() => select(videoSources).watch();

  Future<void> insertVideoSource(VideoSourcesCompanion source) =>
      into(videoSources).insert(source, mode: InsertMode.insertOrReplace);

  Future<void> deleteVideoSource(String id) =>
      (delete(videoSources)..where((t) => t.id.equals(id))).go();

  Future<void> updateVideoSource(VideoSourcesCompanion source) =>
      (update(videoSources)..where((t) => t.id.equals(source.id.value)))
          .write(source);

  // ===== 播放进度 CRUD =====

  /// 保存播放进度（插入或替换）
  Future<void> savePlaybackProgress(PlaybackProgressesCompanion entry) =>
      into(playbackProgresses).insert(entry, mode: InsertMode.insertOrReplace);

  /// 获取指定视频的播放进度
  Future<PlaybackProgress?> getPlaybackProgress(String videoUrl) =>
      (select(playbackProgresses)..where((t) => t.videoUrl.equals(videoUrl)))
          .getSingleOrNull();

  /// 删除指定视频的播放进度
  Future<void> deletePlaybackProgress(String videoUrl) =>
      (delete(playbackProgresses)..where((t) => t.videoUrl.equals(videoUrl)))
          .go();

  // ===== 观看历史 CRUD =====

  Future<void> insertWatchHistory(WatchHistoriesCompanion entry) =>
      into(watchHistories).insert(entry, mode: InsertMode.insertOrReplace);

  Stream<List<WatchHistory>> watchAllWatchHistories() =>
      (select(watchHistories)..orderBy([(t) => OrderingTerm.desc(t.lastWatchTime)])).watch();

  Future<void> deleteWatchHistory(String vodId) =>
      (delete(watchHistories)..where((t) => t.vodId.equals(vodId))).go();

  Future<void> clearAllWatchHistories() => delete(watchHistories).go();

  // ===== 收藏 CRUD =====

  Future<void> insertFavorite(FavoritesCompanion entry) =>
      into(favorites).insert(entry, mode: InsertMode.insertOrReplace);

  Stream<List<Favorite>> watchAllFavorites() =>
      (select(favorites)..orderBy([(t) => OrderingTerm.desc(t.addTime)])).watch();

  Future<Favorite?> getFavorite(String vodId) =>
      (select(favorites)..where((t) => t.vodId.equals(vodId))).getSingleOrNull();

  Future<void> deleteFavorite(String vodId) =>
      (delete(favorites)..where((t) => t.vodId.equals(vodId))).go();

  Stream<bool> isFavoriteStream(String vodId) =>
      (select(favorites)..where((t) => t.vodId.equals(vodId))).watch()
          .map((list) => list.isNotEmpty);

  /// 更新追番集数
  Future<void> updateEpisodeCount(String vodId, int count) =>
      (update(favorites)..where((t) => t.vodId.equals(vodId)))
          .write(FavoritesCompanion(lastEpisodeCount: Value(count)));

  // ===== 下载任务 CRUD =====

  Future<void> insertDownloadTask(DownloadTasksCompanion entry) =>
      into(downloadTasks).insert(entry, mode: InsertMode.insertOrReplace);

  Stream<List<DownloadTask>> watchAllDownloadTasks() =>
      (select(downloadTasks)..orderBy([(t) => OrderingTerm.desc(t.createTime)])).watch();

  Future<void> updateDownloadTask(DownloadTasksCompanion entry) =>
      (update(downloadTasks)..where((t) => t.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteDownloadTask(String id) =>
      (delete(downloadTasks)..where((t) => t.id.equals(id))).go();

  Future<void> deleteCompletedDownloads() =>
      (delete(downloadTasks)..where((t) => t.status.equals(2))).go();

  // ===== 指标事件 CRUD =====

  Future<void> insertMetricsEvent(MetricsEventsCompanion entry) =>
      into(metricsEvents).insert(entry);

  Future<List<MetricsEventRecord>> getUnuploadedEvents({int limit = 50}) =>
      (select(metricsEvents)..where((t) => t.uploaded.equals(false))..limit(limit)).get();

  Future<void> markEventsUploaded(List<String> ids) =>
      (update(metricsEvents)..where((t) => t.id.isIn(ids)))
          .write(const MetricsEventsCompanion(uploaded: Value(true)));

  Future<void> deleteUploadedEvents() =>
      (delete(metricsEvents)..where((t) => t.uploaded.equals(true))).go();

  Future<void> deleteOldEvents({int olderThanDays = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays)).millisecondsSinceEpoch;
    return (delete(metricsEvents)..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();
  }

  // ===== 指标会话 CRUD =====

  Future<void> insertMetricsSession(MetricsSessionsCompanion entry) =>
      into(metricsSessions).insert(entry, mode: InsertMode.insertOrReplace);

  Future<List<MetricsSession>> getUnuploadedSessions({int limit = 50}) =>
      (select(metricsSessions)..where((t) => t.uploaded.equals(false))..limit(limit)).get();

  Future<void> markSessionsUploaded(List<String> ids) =>
      (update(metricsSessions)..where((t) => t.sessionId.isIn(ids)))
          .write(const MetricsSessionsCompanion(uploaded: Value(true)));

  Future<void> deleteUploadedSessions() =>
      (delete(metricsSessions)..where((t) => t.uploaded.equals(true))).go();

  Future<void> deleteOldSessions({int olderThanDays = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays)).millisecondsSinceEpoch;
    return (delete(metricsSessions)..where((t) => t.startTime.isSmallerThanValue(cutoff))).go();
  }

  /// 获取本地指标统计摘要
  Future<Map<String, dynamic>> getMetricsSummary() async {
    final events = await select(metricsEvents).get();
    final sessions = await select(metricsSessions).get();
    return {
      'total_events': events.length,
      'unuploaded_events': events.where((e) => !e.uploaded).length,
      'total_sessions': sessions.length,
      'unuploaded_sessions': sessions.where((s) => !s.uploaded).length,
    };
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'mediamix.db'));
    return NativeDatabase.createInBackground(file);
  });
}

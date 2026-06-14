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

@DriftDatabase(tables: [VideoSources, PlaybackProgresses, WatchHistories, Favorites, DownloadTasks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 6;

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
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'mediamix.db'));
    return NativeDatabase.createInBackground(file);
  });
}

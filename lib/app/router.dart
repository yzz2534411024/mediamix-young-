import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/video/pages/video_home_page.dart';
import '../features/video/pages/video_detail_page.dart';
import '../features/video/pages/player_page.dart';
import '../features/video/pages/video_search_page.dart';
import '../features/video/pages/history_page.dart';
import '../features/video/pages/favorite_page.dart';
import '../features/settings/pages/settings_page.dart';
import '../features/settings/pages/source_manage_page.dart';
import '../features/settings/pages/download_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/video',
    routes: [
      GoRoute(
        path: '/video',
        builder: (context, state) => const VideoHomePage(),
      ),
      GoRoute(
        path: '/detail',
        builder: (context, state) {
          final vodId = state.uri.queryParameters['vodId'] ?? '';
          final sourceKey = state.uri.queryParameters['sourceKey'] ?? '';
          return VideoDetailPage(vodId: vodId, sourceKey: sourceKey);
        },
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) {
          final url = state.uri.queryParameters['url'] ?? '';
          final title = state.uri.queryParameters['title'] ?? '';
          final indexStr = state.uri.queryParameters['index'];
          final epNamesStr = state.uri.queryParameters['epNames'];
          final epUrlsStr = state.uri.queryParameters['epUrls'];
          final qualityLabelsStr = state.uri.queryParameters['qualityLabels'];
          final qualityUrlsStr = state.uri.queryParameters['qualityUrls'];

          final episodeIndex = indexStr != null ? int.tryParse(indexStr) : null;
          final episodeNames = epNamesStr?.split(',');
          final episodeUrls = epUrlsStr?.split(',');
          final qualityLabels = qualityLabelsStr?.isNotEmpty == true
              ? qualityLabelsStr!.split(',')
              : null;
          final qualityUrls = qualityUrlsStr?.isNotEmpty == true
              ? qualityUrlsStr!.split(',')
              : null;

          return PlayerPage(
            url: url,
            title: title,
            episodeIndex: episodeIndex,
            episodeNames: episodeNames,
            episodeUrls: episodeUrls,
            qualityLabels: qualityLabels,
            qualityUrls: qualityUrls,
          );
        },
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const VideoSearchPage(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryPage(),
      ),
      GoRoute(
        path: '/favorite',
        builder: (context, state) => const FavoritePage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/source-manage',
        builder: (context, state) => const SourceManagePage(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (context, state) => const DownloadPage(),
      ),
    ],
  );
});

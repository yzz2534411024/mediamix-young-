package com.mediamix.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.mediamix.ui.navigation.MainScaffold
import com.mediamix.ui.navigation.Screen
import com.mediamix.ui.screens.*

@Composable
fun App() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    // 判断是否显示底部导航栏（播放器、详情页、源码管理页不显示）
    val showBottomBar = currentRoute != Screen.Player.route &&
            currentRoute?.startsWith("detail") != true &&
            currentRoute?.startsWith("player") != true &&
            currentRoute != Screen.SourceManage.route

    MainScaffold(
        currentRoute = currentRoute,
        onNavigate = { screen ->
            navController.navigate(screen.route) {
                popUpTo(Screen.Home.route) { saveState = true }
                launchSingleTop = true
                restoreState = true
            }
        },
        showBottomBar = showBottomBar
    ) { paddingModifier ->
        NavHost(
            navController = navController,
            startDestination = Screen.Home.route,
            modifier = paddingModifier
        ) {
            composable(Screen.Home.route) {
                VideoHomeScreen(
                    onNavigateToDetail = { vodId, sourceKey ->
                        navController.navigate(Screen.Detail.createRoute(vodId, sourceKey))
                    },
                    onNavigateToSearch = {
                        navController.navigate(Screen.Search.route)
                    }
                )
            }
            composable(Screen.History.route) {
                HistoryScreen(
                    onNavigateToDetail = { vodId, sourceKey ->
                        navController.navigate(Screen.Detail.createRoute(vodId, sourceKey))
                    }
                )
            }
            composable(Screen.Favorite.route) {
                FavoriteScreen(
                    onNavigateToDetail = { vodId, sourceKey ->
                        navController.navigate(Screen.Detail.createRoute(vodId, sourceKey))
                    }
                )
            }
            composable(Screen.Settings.route) {
                SettingsScreen(
                    onNavigateToSourceManage = { navController.navigate(Screen.SourceManage.route) },
                    onNavigateToDownloads = { navController.navigate(Screen.Downloads.route) }
                )
            }
            composable("${Screen.Detail.route}?vodId={vodId}&sourceKey={sourceKey}") { backStackEntry ->
                val vodId = backStackEntry.arguments?.getString("vodId") ?: ""
                val sourceKey = backStackEntry.arguments?.getString("sourceKey") ?: ""
                VideoDetailScreen(
                    vodId = vodId,
                    sourceKey = sourceKey,
                    onNavigateToPlayer = { url, title, index ->
                        navController.navigate(Screen.Player.createRoute(url, title, index))
                    },
                    onBack = { navController.popBackStack() }
                )
            }
            composable(Screen.Search.route) {
                VideoSearchScreen(
                    onNavigateToDetail = { vodId, sourceKey ->
                        navController.navigate(Screen.Detail.createRoute(vodId, sourceKey))
                    }
                )
            }
            composable("${Screen.Player.route}?url={url}&title={title}&index={index}") { backStackEntry ->
                val url = backStackEntry.arguments?.getString("url") ?: ""
                val title = backStackEntry.arguments?.getString("title") ?: ""
                val index = backStackEntry.arguments?.getString("index")?.toIntOrNull() ?: 0
                PlayerScreen(
                    url = url,
                    title = title,
                    episodeIndex = index,
                    onBack = { navController.popBackStack() }
                )
            }
            composable(Screen.SourceManage.route) {
                SourceManageScreen(onBack = { navController.popBackStack() })
            }
            composable(Screen.Downloads.route) {
                DownloadScreen(onBack = { navController.popBackStack() })
            }
        }
    }
}

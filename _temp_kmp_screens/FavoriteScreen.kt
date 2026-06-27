package com.mediamix.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mediamix.ui.components.VideoCard
import com.mediamix.ui.viewmodel.FavoriteItem
import com.mediamix.ui.viewmodel.FavoriteViewModel
import org.koin.compose.koinInject

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun FavoriteScreen(
    viewModel: FavoriteViewModel = koinInject(),
    onNavigateToDetail: (vodId: String, sourceKey: String) -> Unit = { _, _ -> }
) {
    val favorites by viewModel.favorites.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    var itemToRemove by remember { mutableStateOf<FavoriteItem?>(null) }

    LaunchedEffect(Unit) {
        viewModel.loadFavorites()
    }

    // Remove confirmation dialog
    itemToRemove?.let { fav ->
        AlertDialog(
            onDismissRequest = { itemToRemove = null },
            title = { Text("取消收藏") },
            text = { Text("确定取消收藏「${fav.vodName}」吗？") },
            confirmButton = {
                Button(onClick = {
                    viewModel.removeFavorite(fav.id)
                    itemToRemove = null
                }) {
                    Text("确定")
                }
            },
            dismissButton = {
                TextButton(onClick = { itemToRemove = null }) {
                    Text("取消")
                }
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("我的收藏") })
        }
    ) { padding ->
        when {
            isLoading -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
            favorites.isEmpty() -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.FavoriteBorder,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                    )
                    Spacer(Modifier.height(16.dp))
                    Text(
                        "暂无收藏",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "在影片详情页点击心形图标收藏",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                    )
                }
            }
            else -> LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                modifier = Modifier.padding(padding),
                contentPadding = PaddingValues(8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                items(favorites, key = { it.id }) { item ->
                    Box(
                        modifier = Modifier.combinedClickable(
                            onClick = {
                                onNavigateToDetail(item.vodId, item.sourceKey)
                            },
                            onLongClick = {
                                itemToRemove = item
                            }
                        )
                    ) {
                        VideoCard(
                            title = item.vodName,
                            coverUrl = item.vodPic,
                            subtitle = item.typeName,
                            onClick = {
                                onNavigateToDetail(item.vodId, item.sourceKey)
                            }
                        )
                    }
                }
            }
        }
    }
}

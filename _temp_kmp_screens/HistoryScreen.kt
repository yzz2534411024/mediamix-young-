package com.mediamix.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.mediamix.ui.viewmodel.HistoryViewModel
import com.mediamix.ui.viewmodel.WatchHistoryItem
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import org.koin.compose.koinInject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel = koinInject(),
    onNavigateToDetail: (vodId: String, sourceKey: String) -> Unit = { _, _ -> }
) {
    val histories by viewModel.histories.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    var showClearDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.loadHistories()
    }

    // Clear confirmation dialog
    if (showClearDialog) {
        AlertDialog(
            onDismissRequest = { showClearDialog = false },
            title = { Text("清空历史") },
            text = { Text("确定要清空所有观看历史吗？") },
            confirmButton = {
                Button(onClick = {
                    viewModel.clearAll()
                    showClearDialog = false
                }) {
                    Text("清空")
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearDialog = false }) {
                    Text("取消")
                }
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("观看历史") },
                actions = {
                    if (histories.isNotEmpty()) {
                        IconButton(onClick = { showClearDialog = true }) {
                            Icon(Icons.Default.DeleteSweep, contentDescription = "清空历史")
                        }
                    }
                }
            )
        }
    ) { padding ->
        when {
            isLoading -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
            histories.isEmpty() -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.History,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                    )
                    Spacer(Modifier.height(16.dp))
                    Text(
                        "暂无观看记录",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                }
            }
            else -> LazyColumn(
                modifier = Modifier.padding(padding),
                contentPadding = PaddingValues(8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(histories, key = { it.id }) { item ->
                    HistorySwipeItem(
                        item = item,
                        onNavigateToDetail = onNavigateToDetail,
                        onDelete = { viewModel.deleteHistory(item.id) }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HistorySwipeItem(
    item: WatchHistoryItem,
    onNavigateToDetail: (vodId: String, sourceKey: String) -> Unit,
    onDelete: () -> Unit
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) {
                onDelete()
                true
            } else {
                false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(MaterialTheme.colorScheme.error),
                contentAlignment = Alignment.CenterEnd
            ) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "删除",
                    tint = Color.White,
                    modifier = Modifier.padding(end = 8.dp)
                )
            }
        },
        enableDismissFromStartToEnd = false
    ) {
        HistoryCard(
            item = item,
            onClick = { onNavigateToDetail(item.vodId, item.sourceKey) }
        )
    }
}

@Composable
private fun HistoryCard(
    item: WatchHistoryItem,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick,
        shape = RoundedCornerShape(12.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier.padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AsyncImage(
                model = item.vodPic,
                contentDescription = item.vodName,
                modifier = Modifier
                    .size(width = 50.dp, height = 70.dp)
                    .clip(RoundedCornerShape(4.dp)),
                contentScale = ContentScale.Crop
            )
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = item.vodName,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(4.dp))
                val subtitle = buildString {
                    if (!item.episodeName.isNullOrEmpty()) append(item.episodeName)
                    append(" · ")
                    append(formatRelativeTime(item.lastWatchTime))
                }
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * 相对时间格式化
 */
private fun formatRelativeTime(timestamp: Long): String {
    if (timestamp <= 0L) return ""
    val now = Clock.System.now().toEpochMilliseconds()
    val diffMs = now - timestamp
    val diffMinutes = diffMs / (60 * 1000)
    val diffHours = diffMs / (60 * 60 * 1000)
    val diffDays = diffMs / (24 * 60 * 60 * 1000)
    return when {
        diffMinutes < 1 -> "刚刚"
        diffHours < 1 -> "${diffMinutes}分钟前"
        diffDays < 1 -> "${diffHours}小时前"
        diffDays < 7 -> "${diffDays}天前"
        else -> {
            val instant = Instant.fromEpochMilliseconds(timestamp)
            val ld = instant.toLocalDateTime(TimeZone.currentSystemDefault())
            "${ld.monthNumber}/${ld.dayOfMonth}"
        }
    }
}

package com.mediamix.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mediamix.shared.player.AspectMode
import com.mediamix.shared.player.PlayMode
import com.mediamix.shared.player.SubtitleTrack

// ============================================================================
// Top Controls Bar
// ============================================================================

@Composable
fun TopControlsBar(
    title: String,
    playbackSpeed: Float,
    qualityLabels: List<String>,
    currentQualityIndex: Int,
    showSubtitles: Boolean,
    subtitleTracks: List<SubtitleTrack>,
    isLocked: Boolean,
    onBack: () -> Unit,
    onSpeedClick: () -> Unit,
    onQualityClick: () -> Unit,
    onSubtitleClick: () -> Unit,
    onMoreClick: () -> Unit,
    onLockClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(Color.Black.copy(alpha = 0.4f))
            .padding(horizontal = 4.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Back button
        IconButton(
            onClick = onBack,
            modifier = Modifier.size(36.dp)
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Back",
                tint = Color.White,
                modifier = Modifier.size(22.dp)
            )
        }

        // Title
        Text(
            text = title,
            color = Color.White,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).padding(horizontal = 4.dp)
        )

        // Speed button
        TextButton(
            onClick = onSpeedClick,
            contentPadding = PaddingValues(horizontal = 6.dp, vertical = 4.dp),
            modifier = Modifier.height(36.dp)
        ) {
            Text("${playbackSpeed}x", color = Color.White, fontSize = 12.sp)
        }

        // Quality button
        if (qualityLabels.size > 1) {
            TextButton(
                onClick = onQualityClick,
                contentPadding = PaddingValues(horizontal = 6.dp, vertical = 4.dp),
                modifier = Modifier.height(36.dp)
            ) {
                Text(
                    text = qualityLabels.getOrElse(currentQualityIndex) { "" },
                    color = Color.White,
                    fontSize = 11.sp
                )
            }
        }

        // Subtitle button
        IconButton(
            onClick = onSubtitleClick,
            modifier = Modifier.size(32.dp)
        ) {
            Icon(
                imageVector = if (showSubtitles) Icons.Default.ClosedCaption else Icons.Default.ClosedCaptionOff,
                contentDescription = "Subtitles",
                tint = if (subtitleTracks.isNotEmpty()) Color.White else Color.White.copy(alpha = 0.3f),
                modifier = Modifier.size(20.dp)
            )
        }

        // More menu
        IconButton(
            onClick = onMoreClick,
            modifier = Modifier.size(36.dp)
        ) {
            Icon(
                imageVector = Icons.Default.MoreVert,
                contentDescription = "More",
                tint = Color.White,
                modifier = Modifier.size(20.dp)
            )
        }

        // Lock button
        IconButton(
            onClick = onLockClick,
            modifier = Modifier.size(32.dp)
        ) {
            Icon(
                imageVector = if (isLocked) Icons.Default.Lock else Icons.Default.LockOpen,
                contentDescription = "Lock",
                tint = Color.White,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

// ============================================================================
// Bottom Controls Bar
// ============================================================================

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BottomControlsBar(
    playMode: PlayMode,
    isPlaying: Boolean,
    hasPrevEpisode: Boolean,
    hasNextEpisode: Boolean,
    skipInterval: Int,
    onPlayModeClick: () -> Unit,
    onPrevEpisode: () -> Unit,
    onRewind: () -> Unit,
    onPlayPause: () -> Unit,
    onForward: () -> Unit,
    onNextEpisode: () -> Unit,
    onSkipIntervalLongClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Play mode
        IconButton(onClick = onPlayModeClick) {
            Icon(
                imageVector = when (playMode) {
                    PlayMode.SEQUENTIAL -> Icons.Default.PlaylistPlay
                    PlayMode.LOOP_SINGLE -> Icons.Default.RepeatOne
                    PlayMode.LOOP_ALL -> Icons.Default.Repeat
                },
                contentDescription = "Play Mode",
                tint = Color.White,
                modifier = Modifier.size(28.dp)
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Previous episode
        if (hasPrevEpisode) {
            IconButton(onClick = onPrevEpisode) {
                Icon(
                    imageVector = Icons.Default.SkipPrevious,
                    contentDescription = "Previous",
                    tint = Color.White,
                    modifier = Modifier.size(32.dp)
                )
            }
            Spacer(modifier = Modifier.width(8.dp))
        }

        // Rewind
        IconButton(
            onClick = onRewind,
            modifier = Modifier.combinedClickable(
                onClick = onRewind,
                onLongClick = onSkipIntervalLongClick
            )
        ) {
            Icon(
                imageVector = Icons.Default.Replay,
                contentDescription = "Rewind",
                tint = Color.White,
                modifier = Modifier.size(32.dp)
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Play/Pause
        IconButton(
            onClick = onPlayPause,
            modifier = Modifier.size(56.dp)
        ) {
            Icon(
                imageVector = if (isPlaying) Icons.Default.PauseCircle else Icons.Default.PlayCircle,
                contentDescription = if (isPlaying) "Pause" else "Play",
                tint = Color.White,
                modifier = Modifier.size(56.dp)
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Forward
        IconButton(
            onClick = onForward,
            modifier = Modifier.combinedClickable(
                onClick = onForward,
                onLongClick = onSkipIntervalLongClick
            )
        ) {
            Icon(
                imageVector = Icons.Default.Forward30,
                contentDescription = "Forward",
                tint = Color.White,
                modifier = Modifier.size(32.dp)
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Next episode
        if (hasNextEpisode) {
            IconButton(onClick = onNextEpisode) {
                Icon(
                    imageVector = Icons.Default.SkipNext,
                    contentDescription = "Next",
                    tint = Color.White,
                    modifier = Modifier.size(32.dp)
                )
            }
        }
    }
}

// ============================================================================
// Progress Bar
// ============================================================================

@Composable
fun PlayerProgressBar(
    positionMs: Long,
    durationMs: Long,
    bufferedPercentage: Int,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    val maxMs = durationMs.coerceAtLeast(1L)
    val sliderValue = positionMs.toFloat().coerceIn(0f, maxMs.toFloat())

    Column(modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Slider(
            value = sliderValue,
            onValueChange = { onSeek(it.toLong()) },
            valueRange = 0f..maxMs.toFloat(),
            colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = Color.White,
                inactiveTrackColor = Color.White.copy(alpha = 0.24f)
            ),
            modifier = Modifier.fillMaxWidth()
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = formatDuration(positionMs),
                color = Color.White,
                fontSize = 12.sp
            )
            Text(
                text = formatDuration(durationMs),
                color = Color.White,
                fontSize = 12.sp
            )
        }
    }
}

// ============================================================================
// Selector Dialogs
// ============================================================================

@Composable
fun SpeedSelectorDialog(
    speeds: List<Float>,
    currentSpeed: Float,
    onSelect: (Float) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF2A2A2A),
        title = { Text("Playback Speed", color = Color.White) },
        text = {
            Column {
                speeds.forEach { speed ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onSelect(speed)
                                onDismiss()
                            }
                            .padding(vertical = 12.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (currentSpeed == speed) {
                            Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(18.dp))
                        } else {
                            Spacer(modifier = Modifier.width(18.dp))
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("${speed}x", color = Color.White, fontSize = 15.sp)
                    }
                }
            }
        },
        confirmButton = {}
    )
}

@Composable
fun QualitySelectorDialog(
    labels: List<String>,
    currentIndex: Int,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF2A2A2A),
        title = { Text("Quality", color = Color.White) },
        text = {
            Column {
                labels.forEachIndexed { index, label ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onSelect(index)
                                onDismiss()
                            }
                            .padding(vertical = 12.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (currentIndex == index) {
                            Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(18.dp))
                        } else {
                            Spacer(modifier = Modifier.width(18.dp))
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(label, color = Color.White, fontSize = 15.sp)
                    }
                }
            }
        },
        confirmButton = {}
    )
}

@Composable
fun SubtitleTrackSelectorDialog(
    tracks: List<SubtitleTrack>,
    currentTrack: Int,
    showSubtitles: Boolean,
    onSelectTrack: (Int) -> Unit,
    onDisable: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF2A2A2A),
        title = { Text("Subtitles", color = Color.White) },
        text = {
            Column {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            onDisable()
                            onDismiss()
                        }
                        .padding(vertical = 12.dp, horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (!showSubtitles) {
                        Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(18.dp))
                    } else {
                        Spacer(modifier = Modifier.width(18.dp))
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Off", color = Color.White, fontSize = 15.sp)
                }
                tracks.forEachIndexed { index, track ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onSelectTrack(index)
                                onDismiss()
                            }
                            .padding(vertical = 12.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (showSubtitles && currentTrack == index) {
                            Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(18.dp))
                        } else {
                            Spacer(modifier = Modifier.width(18.dp))
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(track.label, color = Color.White, fontSize = 15.sp)
                    }
                }
            }
        },
        confirmButton = {}
    )
}

@Composable
fun AspectModeSelectorDialog(
    currentMode: AspectMode,
    onSelect: (AspectMode) -> Unit,
    onDismiss: () -> Unit
) {
    val labels = mapOf(
        AspectMode.ORIGINAL to "Original",
        AspectMode.RATIO_16_9 to "16:9",
        AspectMode.RATIO_4_3 to "4:3",
        AspectMode.FILL to "Fill",
        AspectMode.COVER to "Cover"
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF2A2A2A),
        title = { Text("Aspect Ratio", color = Color.White) },
        text = {
            Column {
                labels.forEach { (mode, label) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onSelect(mode)
                                onDismiss()
                            }
                            .padding(vertical = 12.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (currentMode == mode) {
                            Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(18.dp))
                        } else {
                            Spacer(modifier = Modifier.width(18.dp))
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(label, color = Color.White, fontSize = 15.sp)
                    }
                }
            }
        },
        confirmButton = {}
    )
}

@Composable
fun PowerModeSelectorDialog(
    powerModes: List<Pair<String, String>>,
    currentMode: String,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF2A2A2A),
        title = { Text("Power Mode", color = Color.White) },
        text = {
            Column {
                powerModes.forEach { (mode, label) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onSelect(mode)
                                onDismiss()
                            }
                            .padding(vertical = 12.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (currentMode == mode) {
                            Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(18.dp))
                        } else {
                            Spacer(modifier = Modifier.width(18.dp))
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(label, color = Color.White, fontSize = 15.sp)
                    }
                }
            }
        },
        confirmButton = {}
    )
}

@Composable
fun SkipIntervalSelectorDialog(
    intervals: List<Int>,
    currentInterval: Int,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF2A2A2A),
        title = { Text("Skip Interval", color = Color.White) },
        text = {
            Column {
                intervals.forEach { interval ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onSelect(interval)
                                onDismiss()
                            }
                            .padding(vertical = 12.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (currentInterval == interval) {
                            Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(18.dp))
                        } else {
                            Spacer(modifier = Modifier.width(18.dp))
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("${interval}s", color = Color.White, fontSize = 15.sp)
                    }
                }
            }
        },
        confirmButton = {}
    )
}

@Composable
fun ParserSelectorDialog(
    parsers: List<Pair<String, String>>,
    currentParserKey: String?,
    onSelect: (String?) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF2A2A2A),
        title = { Text("Parser", color = Color.White) },
        text = {
            Column {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            onSelect(null)
                            onDismiss()
                        }
                        .padding(vertical = 12.dp, horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = if (currentParserKey == null) Icons.Default.RadioButtonChecked else Icons.Default.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (currentParserKey == null) Color(0xFF2196F3) else Color.Gray,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Direct", color = Color.White, fontSize = 15.sp)
                }
                parsers.forEach { (key, name) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onSelect(key)
                                onDismiss()
                            }
                            .padding(vertical = 12.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = if (currentParserKey == key) Icons.Default.RadioButtonChecked else Icons.Default.RadioButtonUnchecked,
                            contentDescription = null,
                            tint = if (currentParserKey == key) Color(0xFF2196F3) else Color.Gray,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(name, color = Color.White, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        },
        confirmButton = {}
    )
}

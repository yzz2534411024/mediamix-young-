package com.mediamix.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.mediamix.shared.player.AspectMode
import com.mediamix.shared.player.PlayMode
import com.mediamix.ui.components.*
import com.mediamix.ui.viewmodel.PlayerViewModel
import kotlinx.coroutines.delay
import org.koin.compose.koinInject
import kotlin.math.abs

private const val HIDE_CONTROLS_DELAY_MS = 3000L
private const val SPEED_INDICATOR_DURATION_MS = 3000L
private const val DOUBLE_TAP_ZONE_FRACTION = 0.3f

@Composable
fun PlayerScreen(
    url: String = "",
    title: String = "",
    episodeIndex: Int = 0,
    viewModel: PlayerViewModel = koinInject(),
    onBack: () -> Unit = {}
) {
    // Collect all state from ViewModel
    val playerState by viewModel.playerState.collectAsState()
    val position by viewModel.position.collectAsState()
    val duration by viewModel.duration.collectAsState()
    val bufferedPercentage by viewModel.bufferedPercentage.collectAsState()
    val playbackSpeed by viewModel.playbackSpeed.collectAsState()
    val currentQualityIndex by viewModel.currentQualityIndex.collectAsState()
    val qualityLabels by viewModel.qualityLabels.collectAsState()
    val isLocked by viewModel.isLocked.collectAsState()
    val isSeeking by viewModel.isSeeking.collectAsState()
    val volume by viewModel.volume.collectAsState()
    val brightness by viewModel.brightness.collectAsState()
    val subtitleTracks by viewModel.subtitleTracks.collectAsState()
    val currentSubtitleTrack by viewModel.currentSubtitleTrack.collectAsState()
    val currentEpisodeIndex by viewModel.currentEpisodeIndex.collectAsState()
    val currentEpisodeName by viewModel.currentEpisodeName.collectAsState()
    val playMode by viewModel.playMode.collectAsState()
    val aspectMode by viewModel.aspectMode.collectAsState()
    val isBuffering by viewModel.isBuffering.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val loadingText by viewModel.loadingText.collectAsState()
    val lastError by viewModel.lastError.collectAsState()
    val hasPrevEpisode by viewModel.hasPrevEpisode.collectAsState()
    val hasNextEpisode by viewModel.hasNextEpisode.collectAsState()
    val showSubtitles by viewModel.showSubtitles.collectAsState()
    val speedOptions by viewModel.speedOptions.collectAsState()

    // UI-only state
    var controlsVisible by remember { mutableStateOf(true) }
    var showSpeedIndicator by remember { mutableStateOf(false) }
    var showBrightnessIndicator by remember { mutableStateOf(false) }
    var showVolumeIndicator by remember { mutableStateOf(false) }
    var seekPreviewPositionMs by remember { mutableStateOf(0L) }
    var showSeekPreview by remember { mutableStateOf(false) }

    // Dialog visibility state
    var showSpeedDialog by remember { mutableStateOf(false) }
    var showQualityDialog by remember { mutableStateOf(false) }
    var showSubtitleDialog by remember { mutableStateOf(false) }
    var showAspectDialog by remember { mutableStateOf(false) }
    var showPowerDialog by remember { mutableStateOf(false) }
    var showSkipIntervalDialog by remember { mutableStateOf(false) }
    var showParserDialog by remember { mutableStateOf(false) }

    // More menu
    var showMoreMenu by remember { mutableStateOf(false) }

    // Gesture state
    var isDragLeft by remember { mutableStateOf(false) }
    var dragStartPositionMs by remember { mutableStateOf(0L) }
    var isHorizontalDrag by remember { mutableStateOf(false) }
    var isVerticalDrag by remember { mutableStateOf(false) }

    // Scope for launching coroutines
    val scope = rememberCoroutineScope()

    // Skip interval (hardcoded for now, could be a ViewModel state)
    val skipInterval = 10
    val skipIntervals = listOf(5, 10, 30, 60)

    // Initialize
    LaunchedEffect(url) {
        viewModel.initialize()
        if (url.isNotEmpty()) {
            viewModel.openVideo(url = url, title = title, episodeIndex = episodeIndex)
        }
    }

    // Auto-hide controls
    LaunchedEffect(controlsVisible) {
        if (controlsVisible) {
            delay(HIDE_CONTROLS_DELAY_MS)
            controlsVisible = false
        }
    }

    // Speed indicator auto-hide
    LaunchedEffect(showSpeedIndicator) {
        if (showSpeedIndicator) {
            delay(SPEED_INDICATOR_DURATION_MS)
            showSpeedIndicator = false
        }
    }

    // Determine if playing
    val isPlaying = playerState == com.mediamix.shared.player.PlayerState.PLAYING

    // Dispose on exit
    DisposableEffect(Unit) {
        onDispose { viewModel.dispose() }
    }

    // Helper to show controls and reset timer
    fun showControlsAndReset() {
        controlsVisible = true
    }

    // Main layout
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        // ====================================================================
        // Video surface placeholder
        // ====================================================================
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            // TODO: Platform-specific video rendering surface
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black)
            )
        }

        // ====================================================================
        // Gesture layer
        // ====================================================================
        if (!isLocked) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onTap = {
                                controlsVisible = !controlsVisible
                            },
                            onDoubleTap = { offset ->
                                val screenWidth = size.width.toFloat()
                                if (offset.x < screenWidth * DOUBLE_TAP_ZONE_FRACTION) {
                                    viewModel.fastSeek(position - skipInterval * 1000L)
                                } else if (offset.x > screenWidth * (1f - DOUBLE_TAP_ZONE_FRACTION)) {
                                    viewModel.fastSeek(position + skipInterval * 1000L)
                                } else {
                                    viewModel.togglePlayPause()
                                }
                                showControlsAndReset()
                            }
                        )
                    }
                    .pointerInput(Unit) {
                        detectDragGestures(
                            onDragStart = { offset ->
                                dragStartPositionMs = position
                                isDragLeft = offset.x < size.width / 2
                                isHorizontalDrag = false
                                isVerticalDrag = false
                            },
                            onDrag = { change, dragAmount ->
                                change.consume()
                                val dx = dragAmount.x
                                val dy = -dragAmount.y

                                if (!isHorizontalDrag && !isVerticalDrag) {
                                    if (abs(dx) > 5f || abs(dy) > 5f) {
                                        if (abs(dx) > abs(dy)) {
                                            isHorizontalDrag = true
                                        } else {
                                            isVerticalDrag = true
                                        }
                                    }
                                }

                                if (isHorizontalDrag) {
                                    val screenWidth = size.width.toFloat()
                                    val durationMs = duration.toFloat().coerceAtLeast(1f)
                                    val totalDx = change.position.x - dragAmount.x // approximate
                                    val deltaMs = (dx / screenWidth) * durationMs
                                    val newPos = (dragStartPositionMs + deltaMs.toLong())
                                        .coerceIn(0L, duration)
                                    seekPreviewPositionMs = newPos
                                    showSeekPreview = true
                                    controlsVisible = false
                                } else if (isVerticalDrag) {
                                    val screenHeight = size.height.toFloat()
                                    val delta = dy / screenHeight
                                    if (isDragLeft) {
                                        val newBrightness = (brightness + delta).coerceIn(0f, 1f)
                                        viewModel.setBrightness(newBrightness)
                                        showBrightnessIndicator = true
                                    } else {
                                        val newVolume = (volume + delta).coerceIn(0f, 1f)
                                        viewModel.setVolume(newVolume)
                                        showVolumeIndicator = true
                                    }
                                    controlsVisible = false
                                }
                            },
                            onDragEnd = {
                                if (isHorizontalDrag && showSeekPreview) {
                                    viewModel.fastSeek(seekPreviewPositionMs)
                                }
                                isHorizontalDrag = false
                                isVerticalDrag = false
                                showSeekPreview = false
                                showBrightnessIndicator = false
                                showVolumeIndicator = false
                                showControlsAndReset()
                            }
                        )
                    }
            )
        }

        // ====================================================================
        // UI Overlay Layer
        // ====================================================================

        // Subtitle overlay
        if (showSubtitles && subtitleTracks.isNotEmpty()) {
            SubtitleOverlay(
                subtitleText = null,
                modifier = Modifier.fillMaxSize()
            )
        }

        // Seeking indicator
        if (isSeeking) {
            SeekingOverlay(
                seekPositionText = "Seeking...",
                modifier = Modifier.fillMaxSize()
            )
        }

        // Speed indicator
        if (showSpeedIndicator && playbackSpeed != 1.0f) {
            SpeedIndicator(
                speed = playbackSpeed,
                modifier = Modifier.fillMaxSize()
            )
        }

        // Seek preview position
        if (showSeekPreview) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Surface(
                    color = Color.Black.copy(alpha = 0.87f),
                    shape = MaterialTheme.shapes.medium
                ) {
                    Text(
                        text = formatDuration(seekPreviewPositionMs),
                        color = Color.White,
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)
                    )
                }
            }
        }

        // Lock icon (shown when locked)
        if (isLocked) {
            LockIcon(
                onUnlock = {
                    viewModel.unlockScreen()
                    showControlsAndReset()
                },
                modifier = Modifier.fillMaxSize()
            )
        }

        // Brightness indicator
        if (showBrightnessIndicator) {
            BrightnessIndicator(
                brightness = brightness,
                modifier = Modifier.fillMaxSize()
            )
        }

        // Volume indicator
        if (showVolumeIndicator) {
            VolumeIndicator(
                volume = volume,
                modifier = Modifier.fillMaxSize()
            )
        }

        // Controls layer (shown when visible and not locked)
        if (controlsVisible && !isLocked) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.26f))
                    .pointerInput(Unit) {
                        detectTapGestures(onTap = { /* consume */ })
                    }
            ) {
                // Top bar
                TopControlsBar(
                    title = currentEpisodeName.ifEmpty { title },
                    playbackSpeed = playbackSpeed,
                    qualityLabels = qualityLabels,
                    currentQualityIndex = currentQualityIndex,
                    showSubtitles = showSubtitles,
                    subtitleTracks = subtitleTracks,
                    isLocked = isLocked,
                    onBack = onBack,
                    onSpeedClick = { showSpeedDialog = true },
                    onQualityClick = { showQualityDialog = true },
                    onSubtitleClick = {
                        if (subtitleTracks.size <= 1) {
                            viewModel.toggleSubtitles()
                        } else {
                            showSubtitleDialog = true
                        }
                    },
                    onMoreClick = { showMoreMenu = true },
                    onLockClick = {
                        viewModel.lockScreen()
                        controlsVisible = false
                    }
                )

                Spacer(modifier = Modifier.weight(1f))

                // Progress bar
                PlayerProgressBar(
                    positionMs = position,
                    durationMs = duration,
                    bufferedPercentage = bufferedPercentage,
                    onSeek = { pos ->
                        viewModel.fastSeek(pos)
                        showControlsAndReset()
                    }
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Bottom controls
                BottomControlsBar(
                    playMode = playMode,
                    isPlaying = isPlaying,
                    hasPrevEpisode = hasPrevEpisode,
                    hasNextEpisode = hasNextEpisode,
                    skipInterval = skipInterval,
                    onPlayModeClick = {
                        val next = when (playMode) {
                            PlayMode.SEQUENTIAL -> PlayMode.LOOP_SINGLE
                            PlayMode.LOOP_SINGLE -> PlayMode.LOOP_ALL
                            PlayMode.LOOP_ALL -> PlayMode.SEQUENTIAL
                        }
                        viewModel.setPlayMode(next)
                        showControlsAndReset()
                    },
                    onPrevEpisode = {
                        viewModel.playPrevEpisode()
                        showControlsAndReset()
                    },
                    onRewind = {
                        viewModel.fastSeek(position - skipInterval * 1000L)
                        showControlsAndReset()
                    },
                    onPlayPause = {
                        viewModel.togglePlayPause()
                        showControlsAndReset()
                    },
                    onForward = {
                        viewModel.fastSeek(position + skipInterval * 1000L)
                        showControlsAndReset()
                    },
                    onNextEpisode = {
                        viewModel.playNextEpisode()
                        showControlsAndReset()
                    },
                    onSkipIntervalLongClick = {
                        showSkipIntervalDialog = true
                    }
                )

                Spacer(modifier = Modifier.height(16.dp))
            }
        }

        // Loading overlay
        if (isBuffering || isLoading) {
            LoadingOverlay(
                loadingText = loadingText,
                bufferedPercentage = bufferedPercentage,
                modifier = Modifier.fillMaxSize()
            )
        }

        // Error overlay
        if (lastError != null) {
            ErrorOverlay(
                errorMessage = lastError!!,
                onRetry = { viewModel.retryPlayback() },
                modifier = Modifier.fillMaxSize()
            )
        }

        // More menu (Popup)
        if (showMoreMenu) {
            AlertDialog(
                onDismissRequest = { showMoreMenu = false },
                containerColor = Color(0xFF2A2A2A),
                title = { Text("More", color = Color.White) },
                text = {
                    Column {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    showMoreMenu = false
                                    showAspectDialog = true
                                }
                                .padding(vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.AspectRatio, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Aspect Ratio", color = Color.White)
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    showMoreMenu = false
                                    showPowerDialog = true
                                }
                                .padding(vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Speed, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Power Mode", color = Color.White)
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    showMoreMenu = false
                                    showParserDialog = true
                                }
                                .padding(vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.SettingsInputComponent, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(12.dp))
                            Text("Parser", color = Color.White)
                        }
                    }
                },
                confirmButton = {}
            )
        }
    }

    // ========================================================================
    // Dialogs (outside the Box to avoid z-order issues)
    // ========================================================================

    if (showSpeedDialog) {
        SpeedSelectorDialog(
            speeds = speedOptions,
            currentSpeed = playbackSpeed,
            onSelect = { speed ->
                viewModel.setPlaybackSpeed(speed)
                showSpeedIndicator = true
                showControlsAndReset()
            },
            onDismiss = { showSpeedDialog = false }
        )
    }

    if (showQualityDialog && qualityLabels.size > 1) {
        QualitySelectorDialog(
            labels = qualityLabels,
            currentIndex = currentQualityIndex,
            onSelect = { index ->
                if (index != currentQualityIndex) {
                    viewModel.switchQuality(index)
                }
                showControlsAndReset()
            },
            onDismiss = { showQualityDialog = false }
        )
    }

    if (showSubtitleDialog) {
        SubtitleTrackSelectorDialog(
            tracks = subtitleTracks,
            currentTrack = currentSubtitleTrack,
            showSubtitles = showSubtitles,
            onSelectTrack = { index ->
                viewModel.setSubtitleTrack(index)
                showControlsAndReset()
            },
            onDisable = {
                viewModel.toggleSubtitles()
                showControlsAndReset()
            },
            onDismiss = { showSubtitleDialog = false }
        )
    }

    if (showAspectDialog) {
        AspectModeSelectorDialog(
            currentMode = aspectMode,
            onSelect = { mode ->
                viewModel.setAspectMode(mode)
                showControlsAndReset()
            },
            onDismiss = { showAspectDialog = false }
        )
    }

    if (showPowerDialog) {
        val powerModes = listOf(
            "fullPerformance" to "High Performance",
            "balanced" to "Balanced",
            "powerSaving" to "Power Saving"
        )
        PowerModeSelectorDialog(
            powerModes = powerModes,
            currentMode = "balanced",
            onSelect = { _ ->
                showControlsAndReset()
            },
            onDismiss = { showPowerDialog = false }
        )
    }

    if (showSkipIntervalDialog) {
        SkipIntervalSelectorDialog(
            intervals = skipIntervals,
            currentInterval = skipInterval,
            onSelect = { _ ->
                showControlsAndReset()
            },
            onDismiss = { showSkipIntervalDialog = false }
        )
    }

    if (showParserDialog) {
        ParserSelectorDialog(
            parsers = emptyList(),
            currentParserKey = null,
            onSelect = { _ ->
                showControlsAndReset()
            },
            onDismiss = { showParserDialog = false }
        )
    }
}

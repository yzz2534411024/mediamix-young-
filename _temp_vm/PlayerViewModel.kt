package com.mediamix.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mediamix.shared.player.AspectMode
import com.mediamix.shared.player.PlayerCoreManager
import com.mediamix.shared.player.PlayerState
import com.mediamix.shared.player.PlayMode
import com.mediamix.shared.player.SubtitleTrack
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import co.touchlab.kermit.Logger

/**
 * 播放器 ViewModel
 * 替代: PlayerCoreManager (ChangeNotifier)
 *
 * 桥接 PlayerCoreManager 的回调为 StateFlow 更新。
 */
class PlayerViewModel(
    private val playerCoreManager: PlayerCoreManager,
) : ViewModel() {

    private val logger = Logger.withTag("PlayerViewModel")

    // ===== Playback State =====

    private val _playerState = MutableStateFlow(PlayerState.IDLE)
    val playerState: StateFlow<PlayerState> = _playerState.asStateFlow()

    private val _position = MutableStateFlow(0L)
    val position: StateFlow<Long> = _position.asStateFlow()

    private val _duration = MutableStateFlow(0L)
    val duration: StateFlow<Long> = _duration.asStateFlow()

    private val _bufferedPercentage = MutableStateFlow(0)
    val bufferedPercentage: StateFlow<Int> = _bufferedPercentage.asStateFlow()

    private val _playbackSpeed = MutableStateFlow(1.0f)
    val playbackSpeed: StateFlow<Float> = _playbackSpeed.asStateFlow()

    private val _currentQualityIndex = MutableStateFlow(0)
    val currentQualityIndex: StateFlow<Int> = _currentQualityIndex.asStateFlow()

    private val _qualityLabels = MutableStateFlow<List<String>>(emptyList())
    val qualityLabels: StateFlow<List<String>> = _qualityLabels.asStateFlow()

    private val _isLocked = MutableStateFlow(false)
    val isLocked: StateFlow<Boolean> = _isLocked.asStateFlow()

    private val _isSeeking = MutableStateFlow(false)
    val isSeeking: StateFlow<Boolean> = _isSeeking.asStateFlow()

    private val _volume = MutableStateFlow(1.0f)
    val volume: StateFlow<Float> = _volume.asStateFlow()

    private val _brightness = MutableStateFlow(0.5f)
    val brightness: StateFlow<Float> = _brightness.asStateFlow()

    private val _subtitleTracks = MutableStateFlow<List<SubtitleTrack>>(emptyList())
    val subtitleTracks: StateFlow<List<SubtitleTrack>> = _subtitleTracks.asStateFlow()

    private val _currentSubtitleTrack = MutableStateFlow(0)
    val currentSubtitleTrack: StateFlow<Int> = _currentSubtitleTrack.asStateFlow()

    private val _currentEpisodeIndex = MutableStateFlow(0)
    val currentEpisodeIndex: StateFlow<Int> = _currentEpisodeIndex.asStateFlow()

    private val _currentEpisodeName = MutableStateFlow("")
    val currentEpisodeName: StateFlow<String> = _currentEpisodeName.asStateFlow()

    private val _playMode = MutableStateFlow(PlayMode.SEQUENTIAL)
    val playMode: StateFlow<PlayMode> = _playMode.asStateFlow()

    private val _aspectMode = MutableStateFlow(AspectMode.ORIGINAL)
    val aspectMode: StateFlow<AspectMode> = _aspectMode.asStateFlow()

    private val _isBuffering = MutableStateFlow(false)
    val isBuffering: StateFlow<Boolean> = _isBuffering.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _loadingText = MutableStateFlow("Loading...")
    val loadingText: StateFlow<String> = _loadingText.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    private val _hasPrevEpisode = MutableStateFlow(false)
    val hasPrevEpisode: StateFlow<Boolean> = _hasPrevEpisode.asStateFlow()

    private val _hasNextEpisode = MutableStateFlow(false)
    val hasNextEpisode: StateFlow<Boolean> = _hasNextEpisode.asStateFlow()

    private val _showSubtitles = MutableStateFlow(true)
    val showSubtitles: StateFlow<Boolean> = _showSubtitles.asStateFlow()

    private val _speedOptions = MutableStateFlow(
        listOf(0.25f, 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f, 2.25f, 2.5f, 2.75f, 3.0f)
    )
    val speedOptions: StateFlow<List<Float>> = _speedOptions.asStateFlow()

    // ===== Init =====

    fun initialize() {
        playerCoreManager.onPlayerStateChanged = { state -> _playerState.value = state }
        playerCoreManager.onBufferingChanged = { buffering -> _isBuffering.value = buffering }
        playerCoreManager.onSubtitlesLoaded = { tracks -> _subtitleTracks.value = tracks }
        playerCoreManager.onError = { event -> _lastError.value = event.message }
        syncStateFromManager()
    }

    private fun syncStateFromManager() {
        _playerState.value = playerCoreManager.playerState
        _playbackSpeed.value = playerCoreManager.getPlaybackSpeed()
        _currentQualityIndex.value = playerCoreManager.getCurrentQualityIndex()
        _qualityLabels.value = playerCoreManager.getQualityLabels()
        _volume.value = playerCoreManager.getVolume()
        _brightness.value = playerCoreManager.getBrightness()
        _subtitleTracks.value = playerCoreManager.getSubtitleTracks()
        _currentSubtitleTrack.value = playerCoreManager.getCurrentSubtitleTrack()
        _currentEpisodeIndex.value = playerCoreManager.getCurrentEpisodeIndex()
        _currentEpisodeName.value = playerCoreManager.getCurrentEpisodeName()
        _playMode.value = playerCoreManager.getPlayMode()
        _aspectMode.value = playerCoreManager.getAspectMode()
        _isSeeking.value = playerCoreManager.getIsSeeking()
        _isBuffering.value = playerCoreManager.getIsBuffering()
        _isLoading.value = playerCoreManager.getIsLoading()
        _loadingText.value = playerCoreManager.getLoadingText()
        _lastError.value = playerCoreManager.getLastError()
        _hasPrevEpisode.value = playerCoreManager.getHasPrevEpisode()
        _hasNextEpisode.value = playerCoreManager.getHasNextEpisode()
        _showSubtitles.value = playerCoreManager.getShowSubtitles()
    }

    // ===== Actions =====

    fun openVideo(
        url: String,
        title: String,
        episodeIndex: Int? = null,
        episodeNames: List<String>? = null,
        episodeUrls: List<String>? = null,
        qualityLabels: List<String>? = null,
        qualityUrls: List<String>? = null,
        subtitleUrls: List<String>? = null,
    ) {
        playerCoreManager.initialize(
            url = url, title = title,
            episodeIndex = episodeIndex,
            episodeNames = episodeNames,
            episodeUrls = episodeUrls,
            qualityLabels = qualityLabels,
            qualityUrls = qualityUrls,
            subtitleUrls = subtitleUrls,
        )
        syncStateFromManager()
    }

    fun dispose() { playerCoreManager.dispose() }
    fun togglePlayPause() { playerCoreManager.togglePlayPause(); syncStateFromManager() }
    fun seekTo(positionMs: Long) { playerCoreManager.seekTo(positionMs) }
    fun fastSeek(positionMs: Long) { playerCoreManager.fastSeek(positionMs) }

    fun setPlaybackSpeed(speed: Float) {
        playerCoreManager.setPlaybackSpeed(speed)
        _playbackSpeed.value = speed
    }

    fun setPlayMode(mode: PlayMode) { playerCoreManager.setPlayMode(mode); _playMode.value = mode }
    fun setAspectMode(mode: AspectMode) { playerCoreManager.setAspectMode(mode); _aspectMode.value = mode }
    fun switchQuality(index: Int) { playerCoreManager.switchQuality(index); _currentQualityIndex.value = index }
    fun playPrevEpisode() { playerCoreManager.playPrevEpisode(); syncStateFromManager() }
    fun playNextEpisode() { playerCoreManager.playNextEpisode(); syncStateFromManager() }

    fun setVolume(vol: Float) { playerCoreManager.setVolume(vol); _volume.value = vol }
    fun setBrightness(bright: Float) { playerCoreManager.setBrightness(bright); _brightness.value = bright }

    fun toggleSubtitles() {
        playerCoreManager.toggleSubtitles()
        _showSubtitles.value = !_showSubtitles.value
    }

    fun setSubtitleTrack(index: Int) {
        playerCoreManager.setSubtitleTrack(index)
        _currentSubtitleTrack.value = index
        _showSubtitles.value = true
    }

    fun lockScreen() { _isLocked.value = true }
    fun unlockScreen() { _isLocked.value = false }

    fun retryPlayback() {
        _lastError.value = null
        playerCoreManager.retryPlayback()
    }

    fun updatePosition(positionMs: Long) { _position.value = positionMs }
    fun updateDuration(durationMs: Long) { _duration.value = durationMs }
    fun updateBuffered(percentage: Int) { _bufferedPercentage.value = percentage }

    override fun onCleared() {
        super.onCleared()
        playerCoreManager.dispose()
    }
}

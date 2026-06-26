package com.mediamix.shared.player

import co.touchlab.kermit.Logger
import com.mediamix.shared.core.PowerManager
import com.mediamix.shared.core.PowerMode
import com.mediamix.shared.network.ThroughputPrediction
import com.mediamix.shared.player.engines.*
import com.russhwolf.settings.Settings
import kotlinx.coroutines.*
import kotlinx.datetime.Clock

// ============================================================================
// Constants
// ============================================================================

private const val FIRST_FRAME_TIMEOUT_MS = 10_000L
private const val PRELOAD_TRIGGER_POSITION = 0.8
private const val AV_SYNC_CHECK_INTERVAL_MS = 2_000L
private const val PROGRESS_SAVE_INTERVAL_MS = 10_000L
private const val BACKGROUND_AV_SYNC_INTERVAL_MS = 10_000L
private const val BACKGROUND_PROGRESS_SAVE_INTERVAL_MS = 30_000L
private const val REOPEN_DELAY_MS = 300L
private const val AV_SYNC_SPEED_RECOVERY_MS = 600L
private const val SEEK_OVERLAY_DURATION_MS = 800L
private const val SPEED_INDICATOR_DURATION_MS = 3_000L

// ============================================================================
// Video parser interface (for URL wrapping)
// ============================================================================

/**
 * Video parser interface — wraps original URL for different source parsers.
 */
interface VideoParser {
    val name: String
    fun buildUrl(originalUrl: String): String
}

// ============================================================================
// Progress save callback
// ============================================================================

/**
 * Callback interface for persisting playback progress.
 * Replaces Drift AppDatabase dependency.
 */
interface ProgressSaveCallback {
    fun saveProgress(videoUrl: String, positionMs: Long, durationMs: Long, lastPlayTimeMs: Long)
    suspend fun getProgress(videoUrl: String): PlaybackProgress?
}

data class PlaybackProgress(
    val videoUrl: String,
    val positionMs: Long,
    val durationMs: Long,
    val lastPlayTimeMs: Long
)

// ============================================================================
// PlayerCoreManager — core orchestrator
// ============================================================================

/**
 * Player core manager — orchestrates all playback sub-modules.
 *
 * Migrated from player_core_manager.dart (~955 lines).
 *
 * Core responsibilities:
 * 1. Player lifecycle (init / dispose)
 * 2. Video opening via CacheEngine (cache -> proxy -> direct)
 * 3. Episode switching (prev / next / jump)
 * 4. Quality switching (multi-resolution URL management)
 * 5. Play mode (sequential / loop single / loop all)
 * 6. Playback speed (0.25x - 3.0x, 12 steps)
 * 7. Subtitle management (multi-track loading, track switching)
 * 8. AV sync monitoring (every 2s, tiered correction)
 * 9. Progress saving (every 10s via callback)
 * 10. Error handling (delegated to PlaybackErrorHandler, 9 recovery actions)
 * 11. ABR coordination (throughput prediction -> ABRController)
 * 12. Buffer management (buffer state -> BufferManager)
 */
class PlayerCoreManager(
    private val playerEngine: PlayerEngine,
    private val cacheEngine: CacheEngine,
    private val errorHandler: PlaybackErrorHandler,
    private val metricsEngine: MetricsEngine,
    private val abrController: ABRController,
    private val bufferManager: BufferManager,
    private val subtitleService: SubtitleService,
    private val powerManager: PowerManager,
    private val settings: Settings,
) : PlayerEngineListener {

    private val logger = Logger.withTag("PlayerCoreManager")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // ========================================================================
    // Callbacks (replace ChangeNotifier)
    // ========================================================================

    var onFirstFrame: ((FirstFrameEvent) -> Unit)? = null
    var onError: ((ErrorEvent) -> Unit)? = null
    var onQualitySuggestion: ((QualitySuggestionEvent) -> Unit)? = null
    var onProgressResume: ((ProgressResumeEvent) -> Unit)? = null
    var onQualityAutoSwitch: ((QualityAutoSwitchEvent) -> Unit)? = null
    var onSubtitlesLoaded: ((List<SubtitleTrack>) -> Unit)? = null
    var onBufferingChanged: ((Boolean) -> Unit)? = null
    var onPlayerStateChanged: ((PlayerState) -> Unit)? = null
    var onNotifyPreloadBuffering: ((Boolean) -> Unit)? = null

    // External callbacks
    var progressSaveCallback: ProgressSaveCallback? = null
    var throughputProvider: (() -> ThroughputPrediction)? = null
    var bandwidthProvider: (() -> Double)? = null

    // ========================================================================
    // Internal state
    // ========================================================================

    private var isDisposed = false
    private var isInitialized = false
    private var isInitializing = false
    private var hasTriedDirectUrl = false

    // Video parser
    private var activeParser: VideoParser? = null

    // Playback state
    private var playbackSpeed = 1.0f
    private val speedOptions = listOf(0.25f, 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f, 2.25f, 2.5f, 2.75f, 3.0f)
    private var skipInterval = 10
    private val skipIntervals = listOf(5, 10, 30, 60)
    private var playMode = PlayMode.SEQUENTIAL
    private var aspectMode = AspectMode.ORIGINAL
    private var currentEpisodeIndex = 0
    private var currentEpisodeName = ""
    private var currentQualityIndex = 0
    private var qualityLabels: List<String> = emptyList()
    private var qualityUrls: List<String> = emptyList()
    private var volume = 1.0f
    private var brightness = 0.5f

    // Init params
    private var title = ""
    private var url = ""
    private var episodeNames: List<String>? = null
    private var episodeUrls: List<String>? = null
    private var subtitleUrls: List<String>? = null

    // Subtitles
    private var subtitleTracks: List<SubtitleTrack> = emptyList()
    private var showSubtitles = true
    private var currentSubtitleTrack = 0

    // Hardware decoding / AV sync
    private var hardwareDecodingEnabled = true
    private var avSyncCheckJob: Job? = null
    private var lastVideoPositionMs: Long = 0L
    private var lastPositionUpdateTimeMs: Long = 0L
    private var avSyncCorrectionCount = 0
    private var lastAVSyncCorrectionMs: Long? = null

    // Periodic jobs
    private var progressSaveJob: Job? = null
    private var firstFrameTimeoutJob: Job? = null
    private var seekOverlayJob: Job? = null
    private var speedIndicatorJob: Job? = null

    // Seek
    private var isSeeking = false

    // Preload
    private var hasTriggeredNextEpisodePreload = false
    private var preloadDepth = 1

    // Background / PiP
    private var isInBackground = false
    private var isInPipMode = false
    private var pipSavedQualityIndex: Int? = null
    private var powerMode = PowerMode.BALANCED

    // Loading state
    private var isLoading = false
    private var loadingText = "Loading..."
    private var bufferPercent = 0.0
    private var networkSpeedText = ""

    // Error / cache
    private var lastError: String? = null
    private var fallbackQuality: String? = null
    private var resolvedUrl = ""

    // ========================================================================
    // Public getters
    // ========================================================================

    val playerState: PlayerState get() = playerEngine.getPlayerState()
    fun getPlaybackSpeed(): Float = playbackSpeed
    fun getSpeedOptions(): List<Float> = speedOptions
    fun getSkipInterval(): Int = skipInterval
    fun getSkipIntervals(): List<Int> = skipIntervals
    fun getPlayMode(): PlayMode = playMode
    fun getAspectMode(): AspectMode = aspectMode
    fun getCurrentEpisodeIndex(): Int = currentEpisodeIndex
    fun getCurrentEpisodeName(): String = currentEpisodeName
    fun getCurrentQualityIndex(): Int = currentQualityIndex
    fun getQualityLabels(): List<String> = qualityLabels
    fun getQualityUrls(): List<String> = qualityUrls
    fun hasQualityOptions(): Boolean = qualityUrls.size > 1
    fun getVolume(): Float = volume
    fun getBrightness(): Float = brightness
    fun getSubtitleTracks(): List<SubtitleTrack> = subtitleTracks
    fun getShowSubtitles(): Boolean = showSubtitles
    fun getCurrentSubtitleTrack(): Int = currentSubtitleTrack
    fun getSubtitleService(): SubtitleService = subtitleService
    fun getHardwareDecodingEnabled(): Boolean = hardwareDecodingEnabled
    fun getBufferManager(): BufferManager = bufferManager
    fun getAbrController(): ABRController = abrController
    fun getIsSeeking(): Boolean = isSeeking
    fun getIsBuffering(): Boolean = if (isInitialized) metricsEngine.isBuffering else false
    fun getIsLoading(): Boolean = isLoading
    fun getLoadingText(): String = loadingText
    fun getBufferPercent(): Double = bufferPercent
    fun getNetworkSpeedText(): String = networkSpeedText
    fun getIsWaitingForNetwork(): Boolean = errorHandler.isWaitingForNetwork
    fun getLastError(): String? = lastError
    fun getIsUsingCache(): Boolean = if (isInitialized) cacheEngine.isUsingCache else false
    fun getFallbackQuality(): String? = fallbackQuality
    fun getLastVideoPositionMs(): Long = lastVideoPositionMs
    fun getIsInBackground(): Boolean = isInBackground
    fun getIsInPipMode(): Boolean = isInPipMode
    fun getPowerMode(): PowerMode = powerMode
    fun getHasPrevEpisode(): Boolean = episodeUrls != null && currentEpisodeIndex > 0
    fun getHasNextEpisode(): Boolean = episodeUrls != null && currentEpisodeIndex < (episodeUrls?.size ?: 0) - 1
    fun getIsInitialized(): Boolean = isInitialized
    fun getActiveParser(): VideoParser? = activeParser

    // ========================================================================
    // Initialization
    // ========================================================================

    /**
     * Switch video parser (null = direct connection).
     */
    fun setParser(parser: VideoParser?) {
        activeParser = parser
        hasTriedDirectUrl = false
        playerEngine.stop()
        scope.launch {
            delay(REOPEN_DELAY_MS)
            if (isDisposed) return@launch
            openVideoWithCacheCheck(url, "${title}_$currentEpisodeIndex")
        }
    }

    /**
     * Initialize the player with video parameters.
     */
    fun initialize(
        url: String,
        title: String,
        episodeIndex: Int? = null,
        episodeNames: List<String>? = null,
        episodeUrls: List<String>? = null,
        qualityLabels: List<String>? = null,
        qualityUrls: List<String>? = null,
        subtitleUrls: List<String>? = null,
    ) {
        isInitializing = true
        this.url = url
        this.title = title
        this.episodeNames = episodeNames
        this.episodeUrls = episodeUrls
        this.subtitleUrls = subtitleUrls
        hasTriedDirectUrl = false

        // Configure hardware decoding (non-blocking)
        scope.launch(Dispatchers.Default) {
            configureHardwareDecoding()
        }

        // Set up callbacks
        bufferManager.onBufferStateChanged = { isLow -> onBufferStateChanged(isLow) }
        abrController.onQualityChanged = { level -> onAbrQualityChanged(level) }

        // Set playback parameters
        currentEpisodeIndex = episodeIndex ?: 0
        currentEpisodeName = title
        this.qualityLabels = qualityLabels ?: emptyList()
        this.qualityUrls = qualityUrls ?: emptyList()
        currentQualityIndex = 0
        (errorHandler as? PlaybackErrorHandlerImpl)?.qualityCount = this.qualityUrls.size

        // Set PlayerEngine listener
        playerEngine.setListener(this)

        // Start metrics session
        val videoId = "${title}_${episodeIndex ?: 0}"
        metricsEngine.startSession(videoId)
        metricsEngine.recordEvent(MetricsEvent.PLAY_START)

        // Open video and start periodic tasks
        scope.launch {
            openVideoWithCacheCheck(url, videoId)

            // Set playback speed
            playerEngine.setPlaybackSpeed(playbackSpeed)

            // Start periodic tasks
            startProgressSaveTimer()
            startAvSyncCheckTimer()

            // First frame timeout fallback
            firstFrameTimeoutJob = scope.launch {
                delay(FIRST_FRAME_TIMEOUT_MS)
                if (isDisposed) return@launch
                if (!metricsEngine.hasRecordedFirstFrame && url.isNotEmpty() && !hasTriedDirectUrl) {
                    hasTriedDirectUrl = true
                    logger.w("First frame timeout (10s), bypassing proxy for direct CDN")
                    playerEngine.stop()
                    delay(REOPEN_DELAY_MS)
                    if (isDisposed) return@launch
                    playerEngine.setSource(url)
                }
            }

            // Load preferences
            loadSkipInterval()
            detectPowerMode()

            isInitialized = true
            isInitializing = false
            onPlayerStateChanged?.invoke(playerEngine.getPlayerState())
        }
    }

    // ========================================================================
    // PlayerEngineListener implementation
    // ========================================================================

    override fun onStateChanged(state: PlayerState) {
        if (isDisposed) return
        onPlayerStateChanged?.invoke(playerEngine.getPlayerState())
    }

    override fun onPositionChanged(positionMs: Long) {
        if (isDisposed) return
        lastVideoPositionMs = positionMs
        lastPositionUpdateTimeMs = Clock.System.now().toEpochMilliseconds()

        if (!metricsEngine.hasRecordedFirstFrame && positionMs > 0L) {
            metricsEngine.markFirstFrameRecorded()
            metricsEngine.recordEvent(MetricsEvent.FIRST_FRAME)
            notifyFirstFrame()
            loadSubtitles()
        }
        checkPreloadTrigger(positionMs)
    }

    override fun onBufferChanged(bufferedPercent: Int) {
        if (isDisposed) return
        val bufferMs = bufferedPercent.toLong() * 1000
        bufferManager.updateBuffer(bufferMs)
        abrController.updateBuffer(bufferMs)

        try {
            throughputProvider?.let { abrController.updateThroughputPrediction(it()) }
        } catch (_: Exception) {}

        if (isLoading && bufferedPercent > 0) isLoading = false
        bufferPercent = bufferManager.bufferPercent
        notifyIfNotInitializing()
    }

    override fun onError(error: String, code: Int?) {
        if (isDisposed) return
        logger.e("Playback error: $error")
        metricsEngine.recordEvent(MetricsEvent.ERROR, errorMessage = error)
        handlePlaybackError(error)
    }

    override fun onFirstFrameRendered() {
        if (isDisposed) return
        if (!metricsEngine.hasRecordedFirstFrame) {
            metricsEngine.markFirstFrameRecorded()
            metricsEngine.recordEvent(MetricsEvent.FIRST_FRAME)
            notifyFirstFrame()
            loadSubtitles()
        }
    }

    override fun onPlaybackEnded() {
        if (isDisposed) return
        metricsEngine.recordEvent(MetricsEvent.PLAY_COMPLETE)
        onPlaybackCompleted()
    }

    // ========================================================================
    // Playback controls
    // ========================================================================

    fun play() {
        if (isDisposed) return
        playerEngine.play()
    }

    fun pause() {
        if (isDisposed) return
        playerEngine.pause()
    }

    fun togglePlayPause() {
        if (isDisposed) return
        if (playerEngine.isPlaying()) playerEngine.pause() else playerEngine.play()
    }

    fun seekTo(positionMs: Long) {
        if (isDisposed) return
        playerEngine.seekTo(positionMs)
    }

    fun fastSeek(positionMs: Long) {
        if (isDisposed || isSeeking) return
        isSeeking = true
        metricsEngine.recordEvent(MetricsEvent.SEEK)
        playerEngine.seekTo(positionMs)
        seekOverlayJob?.cancel()
        seekOverlayJob = scope.launch {
            delay(SEEK_OVERLAY_DURATION_MS)
            if (isDisposed) return@launch
            isSeeking = false
        }
    }

    fun setPlaybackSpeed(speed: Float) {
        if (isDisposed) return
        playbackSpeed = speed
        playerEngine.setPlaybackSpeed(speed)
        speedIndicatorJob?.cancel()
        speedIndicatorJob = scope.launch {
            delay(SPEED_INDICATOR_DURATION_MS)
            if (isDisposed) return@launch
        }
    }

    fun setSkipInterval(interval: Int) {
        skipInterval = interval
        saveSkipInterval()
    }

    fun setPlayMode(mode: PlayMode) { playMode = mode }
    fun setAspectMode(mode: AspectMode) { aspectMode = mode }

    fun setVolume(v: Float) {
        volume = v.coerceIn(0f, 1f)
        if (!isDisposed) playerEngine.setVolume(volume * 100f)
    }

    fun setBrightness(b: Float) {
        brightness = b.coerceIn(0f, 1f)
    }

    fun skipForward() {
        val pos = playerEngine.getPosition()
        seekTo(pos + skipInterval * 1000L)
    }

    fun skipBackward() {
        val pos = playerEngine.getPosition()
        seekTo((pos - skipInterval * 1000L).coerceAtLeast(0L))
    }

    // ========================================================================
    // Episode switching
    // ========================================================================

    fun playPrevEpisode() {
        if (getHasPrevEpisode()) playEpisodeAtIndex(currentEpisodeIndex - 1)
    }

    fun playNextEpisode() {
        if (getHasNextEpisode()) playEpisodeAtIndex(currentEpisodeIndex + 1)
    }

    fun playEpisodeAtIndex(index: Int) {
        if (isDisposed) return
        val urls = episodeUrls ?: return
        val names = episodeNames ?: return
        if (index < 0 || index >= urls.size) return
        if (index >= names.size) return

        val videoId = "${title}_$index"
        scope.launch {
            openVideoWithCacheCheck(urls[index], videoId)
        }
        currentEpisodeIndex = index
        currentEpisodeName = names[index]
        hasTriggeredNextEpisodePreload = false
        isLoading = true
        loadingText = "Loading..."
        errorHandler.resetRetryCount()
        errorHandler.clearTriedQualityIndices()
        metricsEngine.startSession(videoId)
        metricsEngine.recordEvent(MetricsEvent.PLAY_START)
        savePlaybackProgress()
    }

    // ========================================================================
    // Quality switching
    // ========================================================================

    fun switchQuality(index: Int) {
        if (isDisposed || index < 0 || index >= qualityUrls.size) return
        val savedPos = playerEngine.getPosition()
        currentQualityIndex = index
        isLoading = true
        loadingText = "Switching quality..."
        scope.launch {
            openVideoWithCacheCheck(qualityUrls[index], "${title}_$index")
            delay(REOPEN_DELAY_MS)
            if (isDisposed) return@launch
            if (savedPos > 0L) playerEngine.seekTo(savedPos)
        }
    }

    // ========================================================================
    // Subtitle controls
    // ========================================================================

    fun toggleSubtitles() { showSubtitles = !showSubtitles }
    fun setSubtitleTrack(index: Int) { currentSubtitleTrack = index; showSubtitles = true }
    fun hideSubtitles() { showSubtitles = false }

    // ========================================================================
    // Play mode
    // ========================================================================

    fun cyclePlayMode() {
        playMode = when (playMode) {
            PlayMode.SEQUENTIAL -> PlayMode.LOOP_ALL
            PlayMode.LOOP_ALL -> PlayMode.LOOP_SINGLE
            PlayMode.LOOP_SINGLE -> PlayMode.SEQUENTIAL
        }
    }

    // ========================================================================
    // Power mode
    // ========================================================================

    fun setPowerMode(mode: PowerMode) {
        powerMode = mode
        applyPowerMode()
    }

    // ========================================================================
    // Retry / Recovery
    // ========================================================================

    fun retryPlayback() {
        if (isDisposed) return
        errorHandler.stopNetworkRecoveryMonitoring()
        errorHandler.resetRetryCount()
        errorHandler.clearTriedQualityIndices()
        lastError = null
        scope.launch {
            openVideoWithCacheCheck(url, "${title}_$currentEpisodeIndex")
        }
    }

    fun resumeToPosition(positionMs: Long) {
        if (!isDisposed) playerEngine.seekTo(positionMs)
    }

    suspend fun checkPlaybackProgress(): Long? {
        val callback = progressSaveCallback ?: return null
        val currentUrl = if (currentEpisodeIndex < (episodeUrls?.size ?: 0)) {
            episodeUrls!![currentEpisodeIndex]
        } else {
            url
        }
        val progress = callback.getProgress(currentUrl) ?: return null
        return if (progress.positionMs > 5000) progress.positionMs else null
    }

    // ========================================================================
    // Preload
    // ========================================================================

    fun preloadAdjacentEpisodes() {
        if (isDisposed) return
        val urls = episodeUrls ?: return
        val depth = preloadDepth.coerceIn(1, 3)
        val indices = ((-depth)..depth)
            .map { currentEpisodeIndex + it }
            .filter { it >= 0 && it < urls.size }
            .filter { it != currentEpisodeIndex }
        cacheEngine.preloadAdjacentEpisodes(indices, title, urls, powerMode)
    }

    fun setPreloadDepth(depth: Int) {
        preloadDepth = depth.coerceIn(1, 3)
    }

    // ========================================================================
    // App lifecycle
    // ========================================================================

    fun onAppLifecycleStateChanged(background: Boolean) {
        if (isDisposed) return
        if (background) onAppBackgrounded() else onAppForegrounded()
    }

    // ========================================================================
    // Delegate methods
    // ========================================================================

    fun findNextUntriedQuality(): Int = errorHandler.findNextUntriedQuality()
    fun clearTriedQualityIndices() = errorHandler.clearTriedQualityIndices()
    fun resetRetryCount() = errorHandler.resetRetryCount()

    // ========================================================================
    // Dispose
    // ========================================================================

    fun dispose() {
        isDisposed = true
        isInitialized = false

        metricsEngine.endSession()
        savePlaybackProgress()

        // Cancel all jobs
        progressSaveJob?.cancel()
        firstFrameTimeoutJob?.cancel()
        seekOverlayJob?.cancel()
        speedIndicatorJob?.cancel()
        avSyncCheckJob?.cancel()

        // Cancel preloads
        cacheEngine.cancelPreloads()

        // Dispose engines
        cacheEngine.dispose()
        errorHandler.dispose()
        metricsEngine.dispose()

        // Release player engine last
        playerEngine.release()
        playerEngine.setListener(null)

        scope.cancel()
    }

    // ========================================================================
    // Internal: Video opening with cache
    // ========================================================================

    private suspend fun openVideoWithCacheCheck(videoUrl: String, videoId: String) {
        if (isDisposed) return
        val effectiveUrl = applyParser(videoUrl)
        try {
            val result = cacheEngine.resolveVideoUrlWithFallback(
                effectiveUrl, videoId, preferredQuality = currentQualityLabel
            )
            if (isDisposed) return
            fallbackQuality = result.fallbackQuality
            if (result.fallbackQuality != null) {
                logger.i("Quality fallback hit: requested $currentQualityLabel, using ${result.fallbackQuality}")
                onQualityAutoSwitch?.invoke(QualityAutoSwitchEvent("${result.fallbackQuality}(cache)"))
            }
            resolvedUrl = result.url
            logger.i("Video URL resolved: ${if (cacheEngine.isUsingCache) "local cache" else "network"}${if (activeParser != null) ", parser: ${activeParser!!.name}" else ""}")
            playerEngine.setSource(resolvedUrl)
        } catch (e: Exception) {
            logger.w("Video URL resolution failed, using original URL: $e")
            resolvedUrl = effectiveUrl
            playerEngine.setSource(effectiveUrl)
        }
    }

    private val currentQualityLabel: String
        get() = if (qualityLabels.isEmpty() || currentQualityIndex >= qualityLabels.size) "720p"
        else qualityLabels[currentQualityIndex]

    private fun applyParser(originalUrl: String): String {
        val parser = activeParser ?: return originalUrl
        return parser.buildUrl(originalUrl)
    }

    // ========================================================================
    // Internal: Error handling — delegated to PlaybackErrorHandler
    // ========================================================================

    private fun handlePlaybackError(error: String) {
        if (isDisposed) return
        lastError = error
        val result = errorHandler.handleError(
            error = error,
            hardwareDecodingEnabled = hardwareDecodingEnabled,
            hasQualityOptions = hasQualityOptions(),
            currentQualityIndex = currentQualityIndex,
            lastPlaybackPositionMs = playerEngine.getPosition(),
        )

        when (result.action) {
            ErrorAction.DOWNGRADE_TO_SOFTWARE_DECODE -> {
                logger.w("Hardware decode failure, downgrading to software decode")
                onHardwareDecodeFailure(error)
            }
            ErrorAction.WAIT_FOR_NETWORK_RECOVERY -> {
                logger.w("Network-related playback interruption, waiting for recovery")
                errorHandler.startNetworkRecoveryMonitoring { attemptReconnect() }
            }
            ErrorAction.RETRY_SAME_URL -> {
                scope.launch {
                    openVideoWithCacheCheck(url, "${title}_$currentEpisodeIndex")
                }
            }
            ErrorAction.SWITCH_TO_NEXT_QUALITY -> {
                val idx = result.nextQualityIndex ?: return
                logger.i("Quality downgrade: ${qualityLabels.getOrElse(currentQualityIndex) { "?" }} -> ${qualityLabels.getOrElse(idx) { "?" }}")
                onQualityAutoSwitch?.invoke(QualityAutoSwitchEvent(qualityLabels.getOrElse(idx) { "" }))
                switchQualityInternal(idx)
            }
            ErrorAction.SHOW_ERROR_DIALOG -> {
                if (!hasTriedDirectUrl && url.isNotEmpty() && url != resolvedUrl) {
                    hasTriedDirectUrl = true
                    logger.w("Proxy chain failed, trying direct CDN URL")
                    playerEngine.stop()
                    scope.launch {
                        delay(REOPEN_DELAY_MS)
                        if (isDisposed) return@launch
                        playerEngine.setSource(url)
                    }
                    return
                }
                val nq = errorHandler.findNextUntriedQuality()
                onError?.invoke(
                    ErrorEvent(
                        message = error,
                        hasNextEpisode = getHasNextEpisode(),
                        hasUntriedQuality = hasQualityOptions() && nq >= 0,
                        untriedQualityLabel = if (nq >= 0) qualityLabels.getOrElse(nq) { null } else null,
                        triedQualityCount = errorHandler.retryCount,
                    )
                )
            }
            ErrorAction.RECOVER_FROM_STUCK -> {
                logger.w("Player stuck detected, attempting seek recovery")
                val pos = playerEngine.getPosition()
                playerEngine.seekTo(if (pos > 0L) pos else 0L)
            }
            ErrorAction.RECOVER_FROM_BLACK_SCREEN -> {
                logger.w("Black screen detected, reinitializing player")
                val blackPos = playerEngine.getPosition()
                playerEngine.release()
                playerEngine.initialize()
                playerEngine.setListener(this)
                scope.launch {
                    openVideoWithCacheCheck(url, "${title}_$currentEpisodeIndex")
                    delay(REOPEN_DELAY_MS)
                    if (isDisposed) return@launch
                    if (blackPos > 0L) playerEngine.seekTo(blackPos)
                }
            }
            ErrorAction.RECOVER_FROM_SILENCE -> {
                logger.w("Silence detected, resetting audio pipeline")
                playerEngine.setAudioTrack("none")
                scope.launch {
                    delay(200)
                    if (!isDisposed) playerEngine.setAudioTrack("auto")
                }
            }
            ErrorAction.SWITCH_SOURCE -> {
                logger.w("Current source abnormal, switching to next source")
                if (hasQualityOptions()) {
                    val nextIdx = result.nextQualityIndex ?: (currentQualityIndex + 1)
                    if (nextIdx < qualityLabels.size) {
                        onQualityAutoSwitch?.invoke(QualityAutoSwitchEvent(qualityLabels[nextIdx]))
                        switchQualityInternal(nextIdx)
                    } else {
                        onError?.invoke(ErrorEvent(message = error, hasNextEpisode = getHasNextEpisode()))
                    }
                } else {
                    onError?.invoke(ErrorEvent(message = error, hasNextEpisode = getHasNextEpisode()))
                }
            }
        }
    }

    private fun attemptReconnect() {
        if (isDisposed) return
        val pos = playerEngine.getPosition()
        logger.i("Auto reconnect - breakpoint: ${pos / 1000}s")
        scope.launch {
            openVideoWithCacheCheck(url, "${title}_$currentEpisodeIndex")
            delay(500)
            if (isDisposed) return@launch
            if (playerEngine.isPlaying() || playerEngine.getPosition() > 0L) {
                playerEngine.seekTo(pos)
                logger.i("Breakpoint restored")
            }
        }
    }

    // ========================================================================
    // Internal: Hardware decode failure
    // ========================================================================

    private fun onHardwareDecodeFailure(error: String) {
        if (isDisposed || !hardwareDecodingEnabled) return
        logger.w("Hardware decode failure, downgrading to software: $error")
        hardwareDecodingEnabled = false
        playerEngine.stop()
        scope.launch {
            delay(REOPEN_DELAY_MS)
            if (isDisposed) return@launch
            openVideoWithCacheCheck(url, "${title}_$currentEpisodeIndex")
        }
    }

    // ========================================================================
    // Internal: Hardware decoding configuration
    // ========================================================================

    private fun configureHardwareDecoding() {
        hardwareDecodingEnabled = true
        logger.d("Hardware decoding configured: $hardwareDecodingEnabled")
    }

    // ========================================================================
    // Internal: Buffer / ABR callbacks
    // ========================================================================

    private fun onBufferStateChanged(isLow: Boolean) {
        if (isDisposed) return
        if (isLow) {
            isLoading = true
            loadingText = "Buffering..."
            metricsEngine.setBuffering(true)
            metricsEngine.recordEvent(MetricsEvent.BUFFER_START)
            cacheEngine.notifyPreloadBuffering(true)
        } else {
            metricsEngine.setBuffering(false)
            metricsEngine.recordEvent(MetricsEvent.BUFFER_END)
            cacheEngine.notifyPreloadBuffering(false)
        }
        onBufferingChanged?.invoke(isLow)
    }

    private fun onAbrQualityChanged(level: QualityLevel) {
        if (isDisposed) return
        logger.i("ABR quality suggestion: ${level.label}")
        abrController.saveQualityPreference(level)
        onQualitySuggestion?.invoke(
            QualitySuggestionEvent(
                networkQualityDescription = abrController.networkQualityDescription,
                qualityLabel = level.label,
            )
        )
    }

    // ========================================================================
    // Internal: AV sync monitoring
    // ========================================================================

    private fun startAvSyncCheckTimer() {
        avSyncCheckJob?.cancel()
        avSyncCheckJob = scope.launch {
            while (isActive && !isDisposed) {
                delay(if (isInBackground) BACKGROUND_AV_SYNC_INTERVAL_MS else AV_SYNC_CHECK_INTERVAL_MS)
                checkAVSync()
            }
        }
    }

    internal fun checkAVSync() {
        if (isDisposed || !playerEngine.isPlaying()) return
        val now = Clock.System.now().toEpochMilliseconds()
        val elapsed = now - lastPositionUpdateTimeMs
        if (elapsed <= 120) return

        val expectedMs = lastVideoPositionMs + elapsed
        val actualMs = playerEngine.getPosition()
        val driftMs = expectedMs - actualMs
        val absDriftMs = kotlin.math.abs(driftMs)
        if (absDriftMs < 50) return

        val frames = absDriftMs / 33

        when {
            absDriftMs > 2000 -> {
                logger.w("Video severely drifted (${absDriftMs}ms / ~$frames frames), seek correction")
                metricsEngine.recordEvent(MetricsEvent.ERROR, avSyncOffsetMs = absDriftMs.toInt())
                if (driftMs < 0) playerEngine.seekTo(expectedMs) else playerEngine.seekTo(actualMs)
                avSyncCorrectionCount++
                lastAVSyncCorrectionMs = now
            }
            absDriftMs > 500 -> {
                logger.w("AV sync offset too large (${absDriftMs}ms), seek correction")
                playerEngine.seekTo(expectedMs)
                avSyncCorrectionCount++
                lastAVSyncCorrectionMs = now
            }
            frames > 5 -> {
                logger.w("Frame accumulation: $frames frames (${absDriftMs}ms), seek to expected")
                playerEngine.seekTo(expectedMs)
                avSyncCorrectionCount++
                lastAVSyncCorrectionMs = now
            }
            else -> {
                logger.d("AV sync micro-adjust: ${driftMs}ms (~$frames frames)")
                val rate = if (driftMs < 0) playbackSpeed * 1.05f else playbackSpeed * 0.95f
                playerEngine.setPlaybackSpeed(rate)
                scope.launch {
                    delay(AV_SYNC_SPEED_RECOVERY_MS)
                    if (isDisposed) return@launch
                    if (playerEngine.isPlaying()) playerEngine.setPlaybackSpeed(playbackSpeed)
                }
            }
        }
    }

    // ========================================================================
    // Internal: Progress save timer
    // ========================================================================

    private fun startProgressSaveTimer() {
        progressSaveJob?.cancel()
        progressSaveJob = scope.launch {
            while (isActive && !isDisposed) {
                delay(if (isInBackground) BACKGROUND_PROGRESS_SAVE_INTERVAL_MS else PROGRESS_SAVE_INTERVAL_MS)
                savePlaybackProgress()
            }
        }
    }

    private fun savePlaybackProgress() {
        if (isDisposed) return
        val callback = progressSaveCallback ?: return
        val videoUrl = if (currentEpisodeIndex < (episodeUrls?.size ?: 0)) {
            episodeUrls!![currentEpisodeIndex]
        } else {
            url
        }
        try {
            callback.saveProgress(
                videoUrl = videoUrl,
                positionMs = playerEngine.getPosition(),
                durationMs = playerEngine.getDuration(),
                lastPlayTimeMs = Clock.System.now().toEpochMilliseconds(),
            )
        } catch (e: Exception) {
            logger.w("Progress save failed: $e")
        }
    }

    // ========================================================================
    // Internal: First frame notification / preload trigger
    // ========================================================================

    private fun notifyFirstFrame() {
        val metrics = metricsEngine.getCurrentMetrics() ?: return
        val ms = (metrics["firstFrameTimeMs"] as? Long) ?: 0L
        if (ms > 0) onFirstFrame?.invoke(FirstFrameEvent(ms))
    }

    private fun checkPreloadTrigger(positionMs: Long) {
        if (isDisposed || hasTriggeredNextEpisodePreload || !getHasNextEpisode()) return
        val duration = playerEngine.getDuration()
        if (duration <= 0) return
        if (positionMs.toFloat() / duration.toFloat() >= PRELOAD_TRIGGER_POSITION) {
            hasTriggeredNextEpisodePreload = true
            val next = currentEpisodeIndex + 1
            cacheEngine.preloadNextEpisode("${title}_$next", episodeUrls!![next])
        }
    }

    // ========================================================================
    // Internal: Subtitle loading
    // ========================================================================

    private fun loadSubtitles() {
        val urls = subtitleUrls ?: return
        if (urls.isEmpty()) return
        scope.launch {
            try {
                val trackInfos = urls.mapIndexed { index, subtitleUrl ->
                    TrackInfo(
                        id = subtitleUrl,
                        label = "Subtitle ${index + 1}",
                        language = "zh-CN",
                    )
                }
                val tracks = subtitleService.loadMultiTrackFromUrl(trackInfos)
                if (isDisposed) return@launch
                subtitleTracks = tracks
                onSubtitlesLoaded?.invoke(tracks)
            } catch (e: Exception) {
                logger.w("Subtitle loading failed: $e")
            }
        }
    }

    // ========================================================================
    // Internal: Playback completed
    // ========================================================================

    private fun onPlaybackCompleted() {
        if (isDisposed) return
        when (playMode) {
            PlayMode.LOOP_SINGLE -> {
                playerEngine.seekTo(0L)
                playerEngine.play()
            }
            PlayMode.LOOP_ALL -> {
                if (getHasNextEpisode()) {
                    playNextEpisode()
                } else if (!episodeUrls.isNullOrEmpty()) {
                    playEpisodeAtIndex(0)
                } else {
                    playerEngine.seekTo(0L)
                    playerEngine.play()
                }
            }
            PlayMode.SEQUENTIAL -> {
                if (getHasNextEpisode()) playNextEpisode()
            }
        }
    }

    // ========================================================================
    // Internal: Quality switching (internal)
    // ========================================================================

    private fun switchQualityInternal(index: Int) {
        if (isDisposed || index < 0 || index >= qualityUrls.size) return
        val savedPos = playerEngine.getPosition()
        currentQualityIndex = index
        isLoading = true
        loadingText = "Switching quality..."
        scope.launch {
            openVideoWithCacheCheck(qualityUrls[index], "${title}_$index")
            delay(REOPEN_DELAY_MS)
            if (isDisposed) return@launch
            if (savedPos > 0L) playerEngine.seekTo(savedPos)
        }
    }

    // ========================================================================
    // Internal: App lifecycle
    // ========================================================================

    private fun onAppBackgrounded() {
        if (isDisposed) return
        isInBackground = true
        logger.d("App backgrounded, keeping audio playback")
        startAvSyncCheckTimer()
        startProgressSaveTimer()
        if (!isInPipMode) savePlaybackProgress()
    }

    private fun onAppForegrounded() {
        if (isDisposed || !isInBackground) return
        isInBackground = false
        logger.d("App foregrounded, restoring video playback")
        startAvSyncCheckTimer()
        startProgressSaveTimer()
        if (isInPipMode && pipSavedQualityIndex != null) {
            isInPipMode = false
            currentQualityIndex = pipSavedQualityIndex!!
            pipSavedQualityIndex = null
            logger.i("PiP exit: restoring original resolution")
        }
    }

    // ========================================================================
    // Internal: Power mode
    // ========================================================================

    private fun detectPowerMode() {
        try {
            powerMode = powerManager.getPowerMode()
            logger.i("Power mode: $powerMode, battery: ${powerManager.getBatteryLevel()}%, charging: ${powerManager.isCharging()}")
            applyPowerMode()
        } catch (e: Exception) {
            powerMode = PowerMode.BALANCED
            logger.d("Power mode detection failed, using default: $e")
        }
    }

    private fun applyPowerMode() {
        if (powerMode == PowerMode.POWER_SAVING) {
            logger.d("Power saving mode: disabling preload")
        }
    }

    // ========================================================================
    // Internal: Preferences
    // ========================================================================

    private fun saveSkipInterval() {
        settings.putInt("skip_interval", skipInterval)
    }

    private fun loadSkipInterval() {
        try {
            val saved = settings.getIntOrNull("skip_interval")
            if (saved != null && saved in skipIntervals) {
                skipInterval = saved
            }
        } catch (e: Exception) {
            logger.w("Skip interval load failed: $e")
        }
    }

    // ========================================================================
    // Internal: Notification control
    // ========================================================================

    private fun notifyIfNotInitializing() {
        if (!isInitializing) {
            onPlayerStateChanged?.invoke(playerEngine.getPlayerState())
        }
    }

    // ========================================================================
    // Utility functions
    // ========================================================================

    companion object {
        fun formatNetworkSpeed(kbps: Double): String = when {
            kbps <= 0 -> ""
            kbps < 1000 -> "${"%.0f".format(kbps)} kb/s"
            else -> "${"%.1f".format(kbps / 1000)} MB/s"
        }

        fun formatDuration(durationMs: Long): String {
            val totalSeconds = durationMs / 1000
            val hours = totalSeconds / 3600
            val minutes = (totalSeconds % 3600) / 60
            val seconds = totalSeconds % 60
            return if (hours > 0) {
                "%d:%02d:%02d".format(hours, minutes, seconds)
            } else {
                "%02d:%02d".format(minutes, seconds)
            }
        }

        fun getPowerModeName(mode: PowerMode): String = when (mode) {
            PowerMode.HIGH_PERFORMANCE -> "High Performance"
            PowerMode.BALANCED -> "Balanced"
            PowerMode.POWER_SAVING -> "Power Saving"
        }
    }
}

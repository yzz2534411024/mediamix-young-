package com.mediamix.shared.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.*

class CacheModelsTest {

    private val json = Json { ignoreUnknownKeys = true }

    // CachePolicy tests

    @Test
    fun test_cachePolicy_hasFourValues() {
        assertEquals(4, CachePolicy.entries.size)
    }

    @Test
    fun test_cachePolicy_values() {
        assertNotNull(CachePolicy.NORMAL)
        assertNotNull(CachePolicy.AGGRESSIVE)
        assertNotNull(CachePolicy.CONSERVATIVE)
        assertNotNull(CachePolicy.EMERGENCY)
    }

    @Test
    fun test_cachePolicy_valueOf() {
        assertEquals(CachePolicy.NORMAL, CachePolicy.valueOf("NORMAL"))
        assertEquals(CachePolicy.EMERGENCY, CachePolicy.valueOf("EMERGENCY"))
    }

    // CachePriority tests

    @Test
    fun test_cachePriority_hasThreeValues() {
        assertEquals(3, CachePriority.entries.size)
    }

    @Test
    fun test_cachePriority_values() {
        assertNotNull(CachePriority.HIGH)
        assertNotNull(CachePriority.NORMAL)
        assertNotNull(CachePriority.LOW)
    }

    // MemoryPressureLevel tests

    @Test
    fun test_memoryPressureLevel_hasFourValues() {
        assertEquals(4, MemoryPressureLevel.entries.size)
    }

    @Test
    fun test_memoryPressureLevel_values() {
        assertNotNull(MemoryPressureLevel.NONE)
        assertNotNull(MemoryPressureLevel.NORMAL)
        assertNotNull(MemoryPressureLevel.WARNING)
        assertNotNull(MemoryPressureLevel.CRITICAL)
    }

    // CacheEntry tests

    @Test
    fun test_cacheEntry_creation_withDefaults() {
        val entry = CacheEntry(cacheId = "c1", videoId = "v1", quality = "1080p", filePath = "/tmp/v1.mp4")
        assertEquals("c1", entry.cacheId)
        assertEquals("v1", entry.videoId)
        assertEquals("1080p", entry.quality)
        assertEquals("/tmp/v1.mp4", entry.filePath)
        assertEquals(0L, entry.fileSize)
        assertTrue(entry.segments.isEmpty())
        assertEquals(0, entry.hitCount)
        assertEquals(0L, entry.lastAccess)
        assertEquals(0L, entry.createdAt)
        assertEquals(604800, entry.ttl)
        assertEquals(0, entry.priority)
        assertTrue(entry.isComplete)
    }

    @Test
    fun test_cacheEntry_isExpired_notExpired() {
        val entry = CacheEntry(
            cacheId = "c1", videoId = "v1", quality = "720p", filePath = "/f",
            createdAt = 1000000L, ttl = 604800
        )
        // currentTimeMillis within TTL
        assertFalse(entry.isExpired(1000000L + 604800L * 1000L - 1))
    }

    @Test
    fun test_cacheEntry_isExpired_expired() {
        val entry = CacheEntry(
            cacheId = "c1", videoId = "v1", quality = "720p", filePath = "/f",
            createdAt = 1000000L, ttl = 604800
        )
        // currentTimeMillis beyond TTL
        assertTrue(entry.isExpired(1000000L + 604800L * 1000L + 1))
    }

    @Test
    fun test_cacheEntry_isExpired_exactBoundary() {
        val entry = CacheEntry(
            cacheId = "c1", videoId = "v1", quality = "720p", filePath = "/f",
            createdAt = 0L, ttl = 100
        )
        // Exactly at expiresAt = 0 + 100*1000 = 100000; currentTime > expiresAt => expired
        assertFalse(entry.isExpired(100000L), "At exact boundary should NOT be expired (> required)")
        assertTrue(entry.isExpired(100001L), "Just past boundary should be expired")
    }

    @Test
    fun test_cacheEntry_copy() {
        val entry = CacheEntry(cacheId = "c1", videoId = "v1", quality = "480p", filePath = "/f")
        val copied = entry.copy(hitCount = 5, quality = "1080p")
        assertEquals(5, copied.hitCount)
        assertEquals("1080p", copied.quality)
        assertEquals("c1", copied.cacheId)
    }

    @Test
    fun test_cacheEntry_equality() {
        val a = CacheEntry(cacheId = "c1", videoId = "v1", quality = "q", filePath = "/f")
        val b = CacheEntry(cacheId = "c1", videoId = "v1", quality = "q", filePath = "/f")
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    @Test
    fun test_cacheEntry_serialization() {
        val entry = CacheEntry(
            cacheId = "c1", videoId = "v1", quality = "1080p", filePath = "/cache/v1.mp4",
            fileSize = 1024L, segments = listOf("seg1", "seg2"), hitCount = 3,
            createdAt = 1000L, ttl = 3600, isComplete = true
        )
        val encoded = json.encodeToString(entry)
        val decoded = json.decodeFromString<CacheEntry>(encoded)
        assertEquals(entry, decoded)
    }

    // SegmentCacheResult tests

    @Test
    fun test_segmentCacheResult_hit() {
        val result = SegmentCacheResult(hit = true, data = listOf(1, 2, 3), path = "/cache/seg1")
        assertTrue(result.hit)
        assertNotNull(result.data)
        assertEquals(3, result.data!!.size)
    }

    @Test
    fun test_segmentCacheResult_miss() {
        val result = SegmentCacheResult(hit = false)
        assertFalse(result.hit)
        assertNull(result.data)
        assertNull(result.path)
    }

    // MemoryUsageInfo tests

    @Test
    fun test_memoryUsageInfo_defaults() {
        val info = MemoryUsageInfo()
        assertEquals(0L, info.l1Bytes)
        assertEquals(0L, info.l2Bytes)
        assertEquals(0L, info.processRssBytes)
        assertEquals(MemoryPressureLevel.NONE, info.pressureLevel)
        assertEquals(0, info.l1MaxEntries)
        assertEquals(0, info.l2MaxEntries)
    }

    @Test
    fun test_memoryUsageInfo_withValues() {
        val info = MemoryUsageInfo(
            l1Bytes = 1024L, l2Bytes = 2048L, processRssBytes = 4096L,
            pressureLevel = MemoryPressureLevel.WARNING, l1MaxEntries = 100, l2MaxEntries = 500
        )
        assertEquals(1024L, info.l1Bytes)
        assertEquals(MemoryPressureLevel.WARNING, info.pressureLevel)
    }

    // CacheStats tests

    @Test
    fun test_cacheStats_defaults() {
        val stats = CacheStats()
        assertEquals(0L, stats.totalSize)
        assertEquals(0, stats.entryCount)
        assertEquals(0L, stats.hitCount)
        assertEquals(0L, stats.missCount)
        assertEquals(0.0, stats.hitRate)
        assertEquals(0.0, stats.diskUsagePercent)
    }

    @Test
    fun test_cacheStats_withValues() {
        val stats = CacheStats(
            totalSize = 1024L * 1024L, entryCount = 50,
            hitCount = 800L, missCount = 200L, hitRate = 0.8, diskUsagePercent = 45.5
        )
        assertEquals(1024L * 1024L, stats.totalSize)
        assertEquals(50, stats.entryCount)
        assertEquals(0.8, stats.hitRate)
    }

    @Test
    fun test_cacheStats_serialization() {
        val stats = CacheStats(totalSize = 2048L, entryCount = 10, hitRate = 0.75)
        val encoded = json.encodeToString(stats)
        val decoded = json.decodeFromString<CacheStats>(encoded)
        assertEquals(stats, decoded)
    }

    // ViewingHabitSnapshot tests

    @Test
    fun test_viewingHabitSnapshot_creation() {
        val snapshot = ViewingHabitSnapshot(
            isPeakHour = true,
            currentHourFrequency = 0.85,
            preferredCategories = listOf("Action", "Drama"),
            highReplayVideoIds = listOf("v1", "v2"),
            predictedCategories = listOf("Action")
        )
        assertTrue(snapshot.isPeakHour)
        assertEquals(0.85, snapshot.currentHourFrequency)
        assertEquals(2, snapshot.preferredCategories.size)
        assertEquals(2, snapshot.highReplayVideoIds.size)
        assertEquals(1, snapshot.predictedCategories.size)
    }

    @Test
    fun test_viewingHabitSnapshot_serialization() {
        val snapshot = ViewingHabitSnapshot(
            isPeakHour = false, currentHourFrequency = 0.5,
            preferredCategories = emptyList(), highReplayVideoIds = emptyList(),
            predictedCategories = emptyList()
        )
        val encoded = json.encodeToString(snapshot)
        val decoded = json.decodeFromString<ViewingHabitSnapshot>(encoded)
        assertEquals(snapshot, decoded)
    }

    // CacheStrategySuggestion tests

    @Test
    fun test_cacheStrategySuggestion_defaults() {
        val suggestion = CacheStrategySuggestion()
        assertEquals(1.0, suggestion.ttlMultiplier)
        assertEquals(1.0, suggestion.capacityMultiplier)
        assertEquals(CachePriority.NORMAL, suggestion.priority)
    }

    @Test
    fun test_cacheStrategySuggestion_defaultSuggestion() {
        val default = CacheStrategySuggestion.defaultSuggestion
        assertEquals(1.0, default.ttlMultiplier)
        assertEquals(1.0, default.capacityMultiplier)
        assertEquals(CachePriority.NORMAL, default.priority)
    }

    @Test
    fun test_cacheStrategySuggestion_customValues() {
        val suggestion = CacheStrategySuggestion(
            ttlMultiplier = 2.0, capacityMultiplier = 0.5, priority = CachePriority.HIGH
        )
        assertEquals(2.0, suggestion.ttlMultiplier)
        assertEquals(0.5, suggestion.capacityMultiplier)
        assertEquals(CachePriority.HIGH, suggestion.priority)
    }

    @Test
    fun test_cacheStrategySuggestion_serialization() {
        val suggestion = CacheStrategySuggestion(ttlMultiplier = 1.5, priority = CachePriority.LOW)
        val encoded = json.encodeToString(suggestion)
        val decoded = json.decodeFromString<CacheStrategySuggestion>(encoded)
        assertEquals(suggestion, decoded)
    }
}

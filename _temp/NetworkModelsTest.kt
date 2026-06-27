package com.mediamix.shared.network

import kotlin.test.*

class NetworkModelsTest {

    // ThroughputPrediction tests

    @Test
    fun test_throughputPrediction_creation() {
        val prediction = ThroughputPrediction(
            predictedKbps = 5000.0,
            confidence = 0.8,
            trendKbps = 200.0,
            longTermAverageKbps = 4500.0,
            stability = 0.9
        )
        assertEquals(5000.0, prediction.predictedKbps)
        assertEquals(0.8, prediction.confidence)
        assertEquals(200.0, prediction.trendKbps)
        assertEquals(4500.0, prediction.longTermAverageKbps)
        assertEquals(0.9, prediction.stability)
    }

    @Test
    fun test_throughputPrediction_empty() {
        val empty = ThroughputPrediction.EMPTY
        assertEquals(0.0, empty.predictedKbps)
        assertEquals(0.0, empty.confidence)
        assertEquals(0.0, empty.trendKbps)
        assertEquals(0.0, empty.longTermAverageKbps)
        assertEquals(0.0, empty.stability)
    }

    @Test
    fun test_throughputPrediction_copy() {
        val original = ThroughputPrediction(1000.0, 0.5, 100.0, 900.0, 0.7)
        val copied = original.copy(predictedKbps = 2000.0)
        assertEquals(2000.0, copied.predictedKbps)
        assertEquals(0.5, copied.confidence)
        assertEquals(original.trendKbps, copied.trendKbps)
    }

    @Test
    fun test_throughputPrediction_equality() {
        val a = ThroughputPrediction(100.0, 0.5, 10.0, 90.0, 0.8)
        val b = ThroughputPrediction(100.0, 0.5, 10.0, 90.0, 0.8)
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    // NetworkConditionLevel tests

    @Test
    fun test_networkConditionLevel_hasThreeValues() {
        assertEquals(3, NetworkConditionLevel.entries.size)
    }

    @Test
    fun test_networkConditionLevel_values() {
        assertNotNull(NetworkConditionLevel.ONLINE)
        assertNotNull(NetworkConditionLevel.WEAK)
        assertNotNull(NetworkConditionLevel.OFFLINE)
    }

    @Test
    fun test_networkConditionLevel_valueOf() {
        assertEquals(NetworkConditionLevel.ONLINE, NetworkConditionLevel.valueOf("ONLINE"))
        assertEquals(NetworkConditionLevel.WEAK, NetworkConditionLevel.valueOf("WEAK"))
        assertEquals(NetworkConditionLevel.OFFLINE, NetworkConditionLevel.valueOf("OFFLINE"))
    }

    @Test
    fun test_networkConditionLevel_ordinalOrder() {
        assertTrue(NetworkConditionLevel.ONLINE.ordinal < NetworkConditionLevel.WEAK.ordinal)
        assertTrue(NetworkConditionLevel.WEAK.ordinal < NetworkConditionLevel.OFFLINE.ordinal)
    }
}

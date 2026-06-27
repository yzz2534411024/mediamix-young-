package com.mediamix.shared.core

import kotlin.test.*

class PowerManagerTest {

    private val powerManager = PowerManager()

    @Test
    fun test_getBatteryLevel_returnsValidRange() {
        val level = powerManager.getBatteryLevel()
        assertTrue(level in 0..100, "Battery level should be 0-100, got $level")
    }

    @Test
    fun test_isCharging_returnsBoolean() {
        val result = powerManager.isCharging()
        assertTrue(result is Boolean, "isCharging should return a Boolean")
    }

    @Test
    fun test_getPowerMode_returnsValidEnum() {
        val mode = powerManager.getPowerMode()
        assertTrue(mode in PowerMode.entries, "Power mode should be a valid PowerMode enum value")
    }

    @Test
    fun test_isBatteryLow_returnsBoolean() {
        val result = powerManager.isBatteryLow()
        assertTrue(result is Boolean, "isBatteryLow should return a Boolean")
    }

    @Test
    fun test_shouldReduceQuality_returnsBoolean() {
        val result = powerManager.shouldReduceQuality()
        assertTrue(result is Boolean, "shouldReduceQuality should return a Boolean")
    }

    // PowerMode enum tests

    @Test
    fun test_powerMode_hasThreeValues() {
        assertEquals(3, PowerMode.entries.size, "PowerMode should have 3 values")
    }

    @Test
    fun test_powerMode_containsExpectedValues() {
        assertNotNull(PowerMode.HIGH_PERFORMANCE)
        assertNotNull(PowerMode.BALANCED)
        assertNotNull(PowerMode.POWER_SAVING)
    }

    @Test
    fun test_powerMode_valueOf() {
        assertEquals(PowerMode.HIGH_PERFORMANCE, PowerMode.valueOf("HIGH_PERFORMANCE"))
        assertEquals(PowerMode.BALANCED, PowerMode.valueOf("BALANCED"))
        assertEquals(PowerMode.POWER_SAVING, PowerMode.valueOf("POWER_SAVING"))
    }
}

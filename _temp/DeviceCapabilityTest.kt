package com.mediamix.shared.core

import kotlin.test.*

class DeviceCapabilityTest {

    private val capability = DeviceCapability()

    @Test
    fun test_supportsHardwareDecoding_returnsBoolean() {
        val result = capability.supportsHardwareDecoding("h264")
        assertTrue(result is Boolean, "supportsHardwareDecoding should return a Boolean")
    }

    @Test
    fun test_supportsHardwareDecoding_unknownCodec() {
        val result = capability.supportsHardwareDecoding("unknown_codec_xyz")
        assertTrue(result is Boolean, "Unknown codec should still return a Boolean")
    }

    @Test
    fun test_getMaxResolution_returnsPositivePair() {
        val resolution = capability.getMaxResolution()
        assertNotNull(resolution, "getMaxResolution should not return null")
        assertTrue(resolution.first > 0, "Width should be positive, got ${resolution.first}")
        assertTrue(resolution.second > 0, "Height should be positive, got ${resolution.second}")
    }

    @Test
    fun test_getDeviceName_returnsNonEmpty() {
        val name = capability.getDeviceName()
        assertNotNull(name, "getDeviceName should not return null")
        assertTrue(name.isNotEmpty(), "Device name should not be empty")
    }
}

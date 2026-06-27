package com.mediamix.shared.network

import kotlin.test.*

class HttpClientFactoryTest {

    @Test
    fun test_createHttpClient_returnsNonNull() {
        val client = HttpClientFactory.createHttpClient()
        assertNotNull(client, "HttpClient should not be null")
        client.close()
    }

    @Test
    fun test_createHttpClient_withCustomTimeout() {
        val client = HttpClientFactory.createHttpClient(
            connectTimeoutSeconds = 5,
            requestTimeoutSeconds = 15
        )
        assertNotNull(client)
        client.close()
    }

    @Test
    fun test_createHttpClient_withCustomUserAgent() {
        val client = HttpClientFactory.createHttpClient(userAgent = "TestAgent/1.0")
        assertNotNull(client)
        client.close()
    }

    @Test
    fun test_createHttpClient_withLoggingEnabled() {
        val client = HttpClientFactory.createHttpClient(enableLogging = true)
        assertNotNull(client)
        client.close()
    }

    @Test
    fun test_createStreamingClient_returnsNonNull() {
        val client = HttpClientFactory.createStreamingClient()
        assertNotNull(client, "Streaming HttpClient should not be null")
        client.close()
    }

    @Test
    fun test_createStreamingClient_withCustomParams() {
        val client = HttpClientFactory.createStreamingClient(
            connectTimeoutSeconds = 20,
            userAgent = "StreamAgent/2.0"
        )
        assertNotNull(client)
        client.close()
    }

    @Test
    fun test_sharedJson_isNotNull() {
        val json = HttpClientFactory.sharedJson
        assertNotNull(json, "sharedJson should not be null")
    }

    @Test
    fun test_sharedJson_isLenient() {
        val json = HttpClientFactory.sharedJson
        assertTrue(json.configuration.isLenient, "sharedJson should be lenient")
    }

    @Test
    fun test_sharedJson_ignoresUnknownKeys() {
        val json = HttpClientFactory.sharedJson
        assertTrue(json.configuration.ignoreUnknownKeys, "sharedJson should ignore unknown keys")
    }
}

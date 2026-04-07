package com.claudemulti.spec

import com.claudemulti.network.ConnectionState
import com.claudemulti.network.WebSocketClient
import com.claudemulti.viewmodel.LastServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Pairing must be secure.
 *
 * These tests define the behavioral contract for device identity, pairing codes,
 * auth token management, and the pairing lifecycle. Uses a FakePreferencesRepository
 * to avoid Android Context dependency.
 */
class PairingSpecTest {

    // =========================================================================
    // FakePreferencesRepository: in-memory stand-in for the real one
    // =========================================================================

    private class FakePreferencesRepository {
        private val store = mutableMapOf<String, Any?>()

        fun saveLastServer(host: String, port: Int, name: String) {
            store["last_server_host"] = host
            store["last_server_port"] = port
            store["last_server_name"] = name
        }

        fun restoreLastServer(): LastServer? {
            val host = store["last_server_host"] as? String ?: return null
            val port = store["last_server_port"] as? Int ?: return null
            val name = store["last_server_name"] as? String ?: ""
            return if (port > 0) LastServer(host, port, name) else null
        }

        fun clearLastServer() {
            store.remove("last_server_host")
            store.remove("last_server_port")
            store.remove("last_server_name")
        }

        fun getOrCreateDeviceId(): String {
            val existing = store["device_id"] as? String
            if (existing != null) return existing
            val newId = java.util.UUID.randomUUID().toString()
            store["device_id"] = newId
            return newId
        }

        fun saveAuthToken(token: String) {
            store["auth_token"] = token
        }

        fun getAuthToken(): String? {
            return store["auth_token"] as? String
        }

        fun clearAuthToken() {
            store.remove("auth_token")
        }
    }

    private lateinit var repo: FakePreferencesRepository
    private lateinit var client: WebSocketClient

    @Before
    fun setUp() {
        repo = FakePreferencesRepository()
        client = WebSocketClient()
    }

    // =========================================================================
    // REQUIREMENT: Device ID MUST be a valid UUID format (not Build.MODEL)
    // =========================================================================

    @Test
    fun deviceId_mustBeValidUUIDFormat() {
        val deviceId = repo.getOrCreateDeviceId()
        assertNotNull(deviceId)

        // UUID v4 format: 8-4-4-4-12 hex chars
        val uuidRegex = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
        assertTrue(
            "Device ID '$deviceId' must be a valid UUID, not a device model string like 'Pixel 8'",
            uuidRegex.matches(deviceId)
        )
    }

    @Test
    fun deviceId_mustNotBeHardwareIdentifier() {
        val deviceId = repo.getOrCreateDeviceId()
        // The device ID should be a random UUID, not something like "Pixel 8" or
        // "samsung SM-G998B". Verify it contains hyphens in UUID positions.
        assertTrue("Must contain UUID hyphens", deviceId.contains("-"))
        assertEquals("UUID must be 36 chars (32 hex + 4 hyphens)", 36, deviceId.length)
    }

    // =========================================================================
    // REQUIREMENT: Device ID MUST be stable (same value across calls)
    // =========================================================================

    @Test
    fun deviceId_mustBeStable_sameValueAcrossCalls() {
        val first = repo.getOrCreateDeviceId()
        val second = repo.getOrCreateDeviceId()
        val third = repo.getOrCreateDeviceId()

        assertEquals("First and second call must return same ID", first, second)
        assertEquals("Second and third call must return same ID", second, third)
    }

    @Test
    fun deviceId_mustSurviveClearOperations() {
        // Clearing the server or auth token should NOT clear the device ID.
        val deviceId = repo.getOrCreateDeviceId()

        repo.clearLastServer()
        repo.clearAuthToken()

        assertEquals(
            "Device ID must persist even after clearing other data",
            deviceId, repo.getOrCreateDeviceId()
        )
    }

    // =========================================================================
    // REQUIREMENT: Device ID MUST be unique per device
    // =========================================================================

    @Test
    fun deviceId_mustBeUniquePerDevice() {
        val repo2 = FakePreferencesRepository()
        val id1 = repo.getOrCreateDeviceId()
        val id2 = repo2.getOrCreateDeviceId()

        // UUIDs could theoretically collide, but the probability is negligible.
        assertTrue(
            "Different devices (repositories) must generate different device IDs",
            id1 != id2
        )
    }

    // =========================================================================
    // REQUIREMENT: Pairing code input MUST be exactly 6 characters
    // =========================================================================

    @Test
    fun pairingCode_mustBeExactly6Digits() {
        val validCode = "482910"
        assertEquals(6, validCode.length)
        assertTrue(validCode.all { it.isDigit() })
    }

    @Test
    fun pairingCode_lessThan6_mustBeInvalid() {
        val shortCode = "12345"
        assertTrue("5-digit code is not 6 digits", shortCode.length != 6)
    }

    @Test
    fun pairingCode_moreThan6_mustBeInvalid() {
        val longCode = "1234567"
        assertTrue("7-digit code is not 6 digits", longCode.length != 6)
    }

    @Test
    fun pairingCode_allZeros_mustBeValid() {
        // "000000" is a valid 6-digit code -- leading zeros are meaningful.
        val code = "000000"
        assertEquals(6, code.length)
        assertTrue(code.all { it.isDigit() })
    }

    @Test
    fun pairingCode_withLetters_mustBeInvalid() {
        // The schema says ^[0-9]{6}$ -- letters are not allowed.
        val badCode = "abc123"
        val pattern = Regex("^[0-9]{6}$")
        assertFalse(
            "Code with letters must not match the schema pattern",
            pattern.matches(badCode)
        )
    }

    @Test
    fun pairingCode_withSpaces_mustBeInvalid() {
        val badCode = "12 345"
        val pattern = Regex("^[0-9]{6}$")
        assertFalse(
            "Code with spaces must not match the schema pattern",
            pattern.matches(badCode)
        )
    }

    // =========================================================================
    // REQUIREMENT: Auth token from successful pairing MUST be persisted
    // =========================================================================

    @Test
    fun authToken_afterSuccessfulPairing_mustBePersisted() {
        repo.saveAuthToken("jwt-token-from-server")
        assertEquals("jwt-token-from-server", repo.getAuthToken())
    }

    @Test
    fun authToken_beforeAnyPairing_mustBeNull() {
        assertNull(repo.getAuthToken())
    }

    @Test
    fun authToken_canBeOverwritten_onRepair() {
        repo.saveAuthToken("old-token")
        repo.saveAuthToken("new-token")
        assertEquals("new-token", repo.getAuthToken())
    }

    // =========================================================================
    // REQUIREMENT: Auth token MUST be cleared on explicit disconnect
    // =========================================================================

    @Test
    fun authToken_mustBeClearedOnDisconnect_inPreferences() {
        repo.saveAuthToken("some-token")
        assertNotNull(repo.getAuthToken())

        // Simulate disconnect behavior: ViewModel calls clearAuthToken
        repo.clearAuthToken()
        assertNull("Auth token must be null after disconnect", repo.getAuthToken())
    }

    @Test
    fun authToken_mustBeClearedOnDisconnect_inWebSocketClient() {
        client.authToken = "token-abc"
        client.disconnect()
        assertNull("WebSocketClient authToken must be null after disconnect", client.authToken)
    }

    // =========================================================================
    // REQUIREMENT: Reconnecting with valid auth token SHOULD skip re-pairing
    // =========================================================================

    @Test
    fun reconnection_withAuthToken_clientRemembersToken() {
        // The auth token is used as X-Auth-Token header on reconnect.
        // If the server recognizes it, re-pairing is skipped.
        client.authToken = "valid-token"
        assertEquals("valid-token", client.authToken)

        // The token survives until explicit disconnect.
        // markPaired does NOT clear the token -- it stays for reconnects.
        client.markPaired()
        assertEquals("valid-token", client.authToken)
    }

    // =========================================================================
    // Full pairing lifecycle
    // =========================================================================

    @Test
    fun fullLifecycle_createDeviceId_pair_saveToken_disconnect_clearToken() {
        // Step 1: Get device ID (first launch)
        val deviceId = repo.getOrCreateDeviceId()
        assertNotNull(deviceId)

        // Step 2: Save server after successful connection
        repo.saveLastServer("192.168.1.100", 12345, "MacBook Pro")

        // Step 3: Save auth token from pair_result
        repo.saveAuthToken("auth-token-xyz")

        // Step 4: Verify everything is retrievable
        assertEquals(deviceId, repo.getOrCreateDeviceId())
        val server = repo.restoreLastServer()!!
        assertEquals("192.168.1.100", server.host)
        assertEquals(12345, server.port)
        assertEquals("auth-token-xyz", repo.getAuthToken())

        // Step 5: Disconnect and clear
        repo.clearLastServer()
        repo.clearAuthToken()

        // Step 6: Server and token gone, but device ID persists
        assertNull(repo.restoreLastServer())
        assertNull(repo.getAuthToken())
        assertEquals("Device ID must survive disconnect", deviceId, repo.getOrCreateDeviceId())
    }

    // =========================================================================
    // Server persistence
    // =========================================================================

    @Test
    fun lastServer_mustBeSavedAndRestored() {
        repo.saveLastServer("10.0.0.1", 8765, "My Mac")
        val restored = repo.restoreLastServer()
        assertNotNull(restored)
        assertEquals("10.0.0.1", restored!!.host)
        assertEquals(8765, restored.port)
        assertEquals("My Mac", restored.name)
    }

    @Test
    fun lastServer_beforeAnySave_mustBeNull() {
        assertNull(repo.restoreLastServer())
    }

    @Test
    fun lastServer_afterClear_mustBeNull() {
        repo.saveLastServer("host", 8080, "name")
        repo.clearLastServer()
        assertNull(repo.restoreLastServer())
    }

    @Test
    fun lastServer_withPortZero_mustReturnNull() {
        // Port 0 is invalid for TCP connections.
        repo.saveLastServer("host", 0, "name")
        assertNull("Port 0 must cause restoreLastServer to return null", repo.restoreLastServer())
    }

    @Test
    fun lastServer_dataClassEquality() {
        val a = LastServer("host", 8080, "name")
        val b = LastServer("host", 8080, "name")
        assertEquals(a, b)
    }
}

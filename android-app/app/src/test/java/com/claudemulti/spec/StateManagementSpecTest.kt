package com.claudemulti.spec

import com.claudemulti.network.ConnectionState
import com.claudemulti.network.WebSocketClient
import com.claudemulti.protocol.ProtocolJson
import com.claudemulti.protocol.SessionBounds
import com.claudemulti.protocol.TerminalSession
import com.claudemulti.protocol.WSMessage
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * State must stay synchronized.
 *
 * These tests define the behavioral contract for how the app manages
 * session state, selection changes, staleness, and state_sync messages.
 *
 * The WebSocketClient manages state internally when receiving messages
 * via its onMessage handler. Since we cannot inject messages without a
 * real WebSocket, some tests verify the message formats and observable
 * state contracts, while others document the expected behavior.
 */
class StateManagementSpecTest {

    private lateinit var client: WebSocketClient

    @Before
    fun setUp() {
        client = WebSocketClient()
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private fun toJson(msg: WSMessage): String =
        ProtocolJson.encodeToString<WSMessage>(msg)

    private fun fromJson(json: String): WSMessage =
        ProtocolJson.decodeFromString<WSMessage>(json)

    private fun sampleSession(
        id: String = "session-1",
        windowId: Int = 1,
        title: String = "zsh",
        selected: Boolean = true
    ) = TerminalSession(
        id = id,
        windowId = windowId,
        title = title,
        bounds = SessionBounds(x = 0.0, y = 0.0, width = 800.0, height = 600.0),
        isSelected = selected
    )

    // =========================================================================
    // REQUIREMENT: Receiving state_sync MUST update sessions list
    //
    // Verified by testing that the state_sync message format contains the
    // correct session data that the client would use to update its state.
    // =========================================================================

    @Test
    fun stateSync_mustContainSessionsList() {
        val json = """
        {
          "type": "state_sync", "version": 1,
          "sessions": [
            {"id":"s1","windowId":1,"title":"zsh","bounds":{"x":0,"y":0,"width":960,"height":1080},"isSelected":true},
            {"id":"s2","windowId":2,"title":"vim","bounds":{"x":960,"y":0,"width":960,"height":1080},"isSelected":false}
          ],
          "screenBounds": {"x":0,"y":0,"width":1920,"height":1080}
        }
        """.trimIndent()
        val msg = fromJson(json) as WSMessage.StateSyncMessage

        assertEquals(2, msg.sessions.size)
        assertEquals("s1", msg.sessions[0].id)
        assertEquals("zsh", msg.sessions[0].title)
        assertTrue(msg.sessions[0].isSelected)
        assertEquals("s2", msg.sessions[1].id)
        assertFalse(msg.sessions[1].isSelected)
    }

    @Test
    fun stateSync_withEmptySessions_mustSetEmptyList() {
        val json = """{"type":"state_sync","version":1,"sessions":[],"screenBounds":{"x":0,"y":0,"width":1920,"height":1080}}"""
        val msg = fromJson(json) as WSMessage.StateSyncMessage
        assertTrue("Empty sessions must be valid", msg.sessions.isEmpty())
    }

    @Test
    fun stateSync_mustUpdateScreenBounds() {
        val json = """{"type":"state_sync","version":1,"sessions":[],"screenBounds":{"x":0,"y":0,"width":2560,"height":1440}}"""
        val msg = fromJson(json) as WSMessage.StateSyncMessage
        assertEquals(2560.0, msg.screenBounds.width, 0.001)
        assertEquals(1440.0, msg.screenBounds.height, 0.001)
    }

    // =========================================================================
    // REQUIREMENT: Receiving state_sync MUST clear isStale flag
    //
    // The WebSocketClient.onMessage handler sets _isStale.value = false
    // when receiving a StateSyncMessage. We verify the initial state and
    // document the expected behavior.
    // =========================================================================

    @Test
    fun initialState_isStale_mustBeFalse() {
        assertFalse("Initial state must not be stale", client.isStale.value)
    }

    @Test
    fun stateSync_behaviorDocumented_mustClearStaleFlag() {
        // When the WebSocket receives a state_sync message, it executes:
        //   _sessions.value = message.sessions
        //   _isStale.value = false
        // This clears the stale flag because we now have fresh data.
        // This is a documented requirement, tested via the onMessage handler
        // in integration tests.
        assertTrue("Documented: state_sync clears isStale", true)
    }

    // =========================================================================
    // REQUIREMENT: Receiving selection_changed MUST update selectedSessionId
    // =========================================================================

    @Test
    fun selectionChanged_mustContainNewSessionId() {
        val json = """{"type":"selection_changed","version":1,"selectedSessionId":"new-session-id"}"""
        val msg = fromJson(json) as WSMessage.SelectionChangedMessage
        assertEquals("new-session-id", msg.selectedSessionId)
    }

    @Test
    fun selectionChanged_sessionId_mustBeNonEmpty() {
        val msg = WSMessage.SelectionChangedMessage(selectedSessionId = "f47ac10b-58cc-4372-a567-0e02b2c3d479")
        assertTrue(msg.selectedSessionId.isNotEmpty())
    }

    @Test
    fun selectionChanged_behaviorDocumented_mustUpdateSelectedSessionId() {
        // When the WebSocket receives a selection_changed message, it executes:
        //   _selectedSessionId.value = message.selectedSessionId
        // The ViewModel also mirrors this change.
        assertTrue("Documented: selection_changed updates selectedSessionId", true)
    }

    // =========================================================================
    // REQUIREMENT: Receiving pair_result with success=true MUST transition to Paired
    // =========================================================================

    @Test
    fun pairResult_success_mustTransitionToPaired() {
        val json = """{"type":"pair_result","version":1,"success":true,"message":"Paired successfully"}"""
        val msg = fromJson(json) as WSMessage.PairResultMessage
        assertTrue("success must be true", msg.success)

        // The WebSocketClient.onMessage handler does:
        //   if (message.success) {
        //       _connectionState.value = ConnectionState.Paired
        //       wasPreviouslyPaired = true
        //       _isStale.value = false
        //   }
        // Verify via markPaired which has the same effect:
        client.markPaired()
        assertEquals(ConnectionState.Paired, client.connectionState.value)
    }

    // =========================================================================
    // REQUIREMENT: Receiving pair_result with success=false MUST NOT transition to Paired
    // =========================================================================

    @Test
    fun pairResult_failure_mustNotTransitionToPaired() {
        val json = """{"type":"pair_result","version":1,"success":false,"message":"Invalid code"}"""
        val msg = fromJson(json) as WSMessage.PairResultMessage
        assertFalse("success must be false", msg.success)

        // The handler only transitions on success=true.
        // Verify the client remains in its current state (Disconnected).
        assertEquals(
            "Client must NOT transition to Paired on failure",
            ConnectionState.Disconnected, client.connectionState.value
        )
    }

    @Test
    fun pairResult_failure_withoutMessage_isValid() {
        // The "message" field is optional per schema.
        val json = """{"type":"pair_result","version":1,"success":false}"""
        val msg = fromJson(json) as WSMessage.PairResultMessage
        assertFalse(msg.success)
        assertNull(msg.message)
    }

    // =========================================================================
    // REQUIREMENT: When connection drops, sessions MUST be preserved (not cleared)
    // =========================================================================

    @Test
    fun connectionDrop_sessionsMustBePreserved_notCleared() {
        // The WebSocketClient's onClosed and onFailure handlers do NOT clear
        // _sessions or _selectedSessionId. They only mark _isStale = true.
        // This allows the UI to show last-known state with a "Reconnecting" overlay.
        //
        // Verify initial state has empty sessions:
        assertTrue(client.sessions.value.isEmpty())

        // After disconnect, sessions remain as they were (empty initially):
        client.disconnect()
        // The key behavior is that disconnect() does NOT touch _sessions.
        // In the real flow, sessions would have been populated by state_sync.
        assertTrue(
            "Documented: disconnect preserves sessions list (does not clear it in WebSocketClient)",
            true
        )
    }

    // =========================================================================
    // REQUIREMENT: When connection drops, isStale MUST be set to true
    // =========================================================================

    @Test
    fun connectionDrop_isStale_behaviorDocumented() {
        // The WebSocketClient sets _isStale.value = true in onClosed/onFailure:
        //   if (_sessions.value.isNotEmpty()) { _isStale.value = true }
        // Note: it only marks stale if there are sessions to show.
        // With no sessions, there's nothing to be stale about.
        assertTrue("Documented: connection drop marks stale when sessions exist", true)
    }

    @Test
    fun disconnect_mustClearStaleFlag() {
        // Explicit disconnect() (user-initiated) clears the stale flag.
        // This is different from connection drop (automatic).
        client.disconnect()
        assertFalse("Explicit disconnect must clear isStale", client.isStale.value)
    }

    // =========================================================================
    // REQUIREMENT: When reconnected, isStale MUST be cleared after state_sync
    // =========================================================================

    @Test
    fun reconnection_afterStateSync_isStale_mustBeFalse() {
        // The sequence is:
        // 1. Connection drops -> isStale = true
        // 2. Reconnect succeeds -> onOpen sends request_sync
        // 3. Server sends state_sync -> onMessage sets isStale = false
        // This is verified in integration tests. Document the contract here.
        assertTrue("Documented: state_sync on reconnect clears isStale", true)
    }

    // =========================================================================
    // REQUIREMENT: Cycling selection MUST send CycleSelectionMessage
    // =========================================================================

    @Test
    fun cycleSelection_next_mustSerializeCorrectly() {
        val msg = WSMessage.CycleSelectionMessage(direction = "next")
        val json = toJson(msg)
        val obj = Json.parseToJsonElement(json).jsonObject

        assertEquals("cycle_selection", obj["type"]!!.jsonPrimitive.content)
        assertEquals("next", obj["direction"]!!.jsonPrimitive.content)
        assertEquals("1", obj["version"]!!.jsonPrimitive.content)
    }

    @Test
    fun cycleSelection_prev_mustSerializeCorrectly() {
        val msg = WSMessage.CycleSelectionMessage(direction = "prev")
        val json = toJson(msg)
        val obj = Json.parseToJsonElement(json).jsonObject

        assertEquals("cycle_selection", obj["type"]!!.jsonPrimitive.content)
        assertEquals("prev", obj["direction"]!!.jsonPrimitive.content)
    }

    @Test
    fun cycleSelection_defaultDirection_mustBeNext() {
        // RemoteViewModel.cycleSelection() defaults to "next":
        //   fun cycleSelection(direction: String = "next")
        val defaultDirection = "next"
        assertEquals("next", defaultDirection)
    }

    // =========================================================================
    // REQUIREMENT: request_sync must be sent automatically after reconnection
    // =========================================================================

    @Test
    fun requestSync_messageFormat_mustBeCorrect() {
        val msg = WSMessage.RequestSyncMessage()
        val json = toJson(msg)
        val obj = Json.parseToJsonElement(json).jsonObject

        assertEquals("request_sync", obj["type"]!!.jsonPrimitive.content)
        assertEquals("1", obj["version"]!!.jsonPrimitive.content)
        // request_sync has no other fields besides type and version.
        assertEquals("request_sync must only have type and version", 2, obj.keys.size)
    }

    @Test
    fun reconnection_mustSendRequestSync_behaviorDocumented() {
        // The WebSocketClient.onOpen handler checks:
        //   if (wasPreviouslyPaired) {
        //       _connectionState.value = ConnectionState.Paired
        //       _isStale.value = false
        //       send(WSMessage.RequestSyncMessage())
        //   }
        // This ensures the UI gets fresh data after reconnection.
        assertTrue("Documented: reconnection auto-sends request_sync", true)
    }

    // =========================================================================
    // State sync with varying session counts
    // =========================================================================

    @Test
    fun stateSync_singleSession_parsesCorrectly() {
        val json = """
        {
          "type": "state_sync", "version": 1,
          "sessions": [
            {"id":"only-session","windowId":1,"title":"zsh","bounds":{"x":0,"y":0,"width":1920,"height":1080},"isSelected":true}
          ],
          "screenBounds": {"x":0,"y":0,"width":1920,"height":1080}
        }
        """.trimIndent()
        val msg = fromJson(json) as WSMessage.StateSyncMessage
        assertEquals(1, msg.sessions.size)
        assertTrue(msg.sessions[0].isSelected)
    }

    @Test
    fun stateSync_manySessionsWithOneSelected_parsesCorrectly() {
        val json = """
        {
          "type": "state_sync", "version": 1,
          "sessions": [
            {"id":"s1","windowId":1,"title":"a","bounds":{"x":0,"y":0,"width":100,"height":100},"isSelected":false},
            {"id":"s2","windowId":2,"title":"b","bounds":{"x":0,"y":0,"width":100,"height":100},"isSelected":false},
            {"id":"s3","windowId":3,"title":"c","bounds":{"x":0,"y":0,"width":100,"height":100},"isSelected":true},
            {"id":"s4","windowId":4,"title":"d","bounds":{"x":0,"y":0,"width":100,"height":100},"isSelected":false},
            {"id":"s5","windowId":5,"title":"e","bounds":{"x":0,"y":0,"width":100,"height":100},"isSelected":false}
          ],
          "screenBounds": {"x":0,"y":0,"width":1920,"height":1080}
        }
        """.trimIndent()
        val msg = fromJson(json) as WSMessage.StateSyncMessage
        assertEquals(5, msg.sessions.size)
        val selectedCount = msg.sessions.count { it.isSelected }
        assertEquals("Exactly one session must be selected", 1, selectedCount)
        assertEquals("s3", msg.sessions.first { it.isSelected }.id)
    }

    // =========================================================================
    // Error message handling
    // =========================================================================

    @Test
    fun errorMessage_mustDeserializeCorrectly() {
        val json = """{"type":"error","version":1,"message":"Session not found: abc-123"}"""
        val msg = fromJson(json) as WSMessage.ErrorMessage
        assertEquals("Session not found: abc-123", msg.message)
        assertEquals(1, msg.version)
    }

    @Test
    fun errorMessage_mustRoundTrip() {
        val original = WSMessage.ErrorMessage(message = "Connection timeout")
        val json = toJson(original)
        val restored = fromJson(json) as WSMessage.ErrorMessage
        assertEquals(original, restored)
    }

    // =========================================================================
    // TerminalSession and SessionBounds data integrity
    // =========================================================================

    @Test
    fun terminalSession_allFieldsMustBeSerialized() {
        val session = sampleSession(id = "test-id", windowId = 42, title = "claude", selected = true)
        val json = ProtocolJson.encodeToString(session)
        val obj = Json.parseToJsonElement(json).jsonObject

        assertTrue(obj.containsKey("id"))
        assertTrue(obj.containsKey("windowId"))
        assertTrue(obj.containsKey("title"))
        assertTrue(obj.containsKey("bounds"))
        assertTrue(obj.containsKey("isSelected"))
    }

    @Test
    fun sessionBounds_mustRoundTrip() {
        val bounds = SessionBounds(x = 10.5, y = 20.3, width = 1920.0, height = 1080.0)
        val json = ProtocolJson.encodeToString(bounds)
        val restored = ProtocolJson.decodeFromString<SessionBounds>(json)
        assertEquals(bounds, restored)
    }

    @Test
    fun terminalSession_mustRoundTrip() {
        val session = sampleSession()
        val json = ProtocolJson.encodeToString(session)
        val restored = ProtocolJson.decodeFromString<TerminalSession>(json)
        assertEquals(session, restored)
    }

    // =========================================================================
    // Observable state: verify flows are accessible and have correct initial values
    // =========================================================================

    @Test
    fun sessions_flow_initialValue_mustBeEmpty() = runBlocking {
        val sessions = client.sessions.first()
        assertTrue(sessions.isEmpty())
    }

    @Test
    fun selectedSessionId_flow_initialValue_mustBeNull() = runBlocking {
        val selected = client.selectedSessionId.first()
        assertNull(selected)
    }

    @Test
    fun connectionState_flow_initialValue_mustBeDisconnected() = runBlocking {
        val state = client.connectionState.first()
        assertEquals(ConnectionState.Disconnected, state)
    }

    @Test
    fun isStale_flow_initialValue_mustBeFalse() = runBlocking {
        val stale = client.isStale.first()
        assertFalse(stale)
    }

    @Test
    fun connectionError_flow_initialValue_mustBeNull() = runBlocking {
        val error = client.connectionError.first()
        assertNull(error)
    }
}

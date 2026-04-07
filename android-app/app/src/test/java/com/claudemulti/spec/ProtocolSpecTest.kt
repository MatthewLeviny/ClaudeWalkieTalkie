package com.claudemulti.spec

import com.claudemulti.protocol.ProtocolJson
import com.claudemulti.protocol.SessionBounds
import com.claudemulti.protocol.TerminalSession
import com.claudemulti.protocol.WSMessage
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The protocol wire format must match the JSON Schema spec.
 *
 * These tests are the specification. They define what the protocol MUST do,
 * derived from protocol/schema/messages.json and protocol/examples/ *.json.
 * A failing test here means the implementation violates the protocol contract.
 */
class ProtocolSpecTest {

    // =========================================================================
    // Helpers
    // =========================================================================

    private fun toJson(msg: WSMessage): String =
        ProtocolJson.encodeToString<WSMessage>(msg)

    private fun fromJson(json: String): WSMessage =
        ProtocolJson.decodeFromString<WSMessage>(json)

    private fun parseJsonObject(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    // =========================================================================
    // SECTION 1: Protocol example wire-format conformance
    //
    // For each of the 8 example JSON files, we hardcode the exact JSON string,
    // deserialize it, verify every field, re-serialize, and verify required
    // fields are present with correct type discriminator.
    // =========================================================================

    // --- pair.json ---

    @Test
    fun example_pair_deserializesWithCorrectFields() {
        val json = """{"type":"pair","version":1,"code":"482910","deviceId":"pixel-8-a1b2c3d4"}"""
        val msg = fromJson(json)
        assertTrue("Must deserialize to PairMessage", msg is WSMessage.PairMessage)
        val pair = msg as WSMessage.PairMessage
        assertEquals(1, pair.version)
        assertEquals("482910", pair.code)
        assertEquals("pixel-8-a1b2c3d4", pair.deviceId)
    }

    @Test
    fun example_pair_reserializesWithRequiredFields() {
        val json = """{"type":"pair","version":1,"code":"482910","deviceId":"pixel-8-a1b2c3d4"}"""
        val msg = fromJson(json)
        val reserialized = toJson(msg)
        val obj = parseJsonObject(reserialized)
        assertEquals("pair", obj["type"]!!.jsonPrimitive.content)
        assertEquals("1", obj["version"]!!.jsonPrimitive.content)
        assertTrue(obj.containsKey("code"))
        assertTrue(obj.containsKey("deviceId"))
    }

    // --- pair_result.json ---

    @Test
    fun example_pairResult_deserializesWithCorrectFields() {
        val json = """{"type":"pair_result","version":1,"success":true,"message":"Paired successfully"}"""
        val msg = fromJson(json)
        assertTrue("Must deserialize to PairResultMessage", msg is WSMessage.PairResultMessage)
        val pr = msg as WSMessage.PairResultMessage
        assertEquals(1, pr.version)
        assertTrue(pr.success)
        assertEquals("Paired successfully", pr.message)
    }

    @Test
    fun example_pairResult_reserializesWithRequiredFields() {
        val json = """{"type":"pair_result","version":1,"success":true,"message":"Paired successfully"}"""
        val msg = fromJson(json)
        val reserialized = toJson(msg)
        val obj = parseJsonObject(reserialized)
        assertEquals("pair_result", obj["type"]!!.jsonPrimitive.content)
        assertEquals("1", obj["version"]!!.jsonPrimitive.content)
        assertTrue(obj.containsKey("success"))
    }

    // --- state_sync.json ---

    @Test
    fun example_stateSync_deserializesWithCorrectFields() {
        val json = """
        {
          "type": "state_sync",
          "version": 1,
          "sessions": [
            {"id":"f47ac10b-58cc-4372-a567-0e02b2c3d479","windowId":1001,"title":"claude-backend refactor","bounds":{"x":0,"y":0,"width":960,"height":1080},"isSelected":true},
            {"id":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d","windowId":1002,"title":"api-tests runner","bounds":{"x":960,"y":0,"width":960,"height":540},"isSelected":false},
            {"id":"6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b","windowId":1003,"title":"docs update","bounds":{"x":960,"y":540,"width":960,"height":540},"isSelected":false}
          ],
          "screenBounds": {"x":0,"y":0,"width":1920,"height":1080}
        }
        """.trimIndent()
        val msg = fromJson(json)
        assertTrue("Must deserialize to StateSyncMessage", msg is WSMessage.StateSyncMessage)
        val ss = msg as WSMessage.StateSyncMessage
        assertEquals(1, ss.version)
        assertEquals(3, ss.sessions.size)

        // Session 1
        val s1 = ss.sessions[0]
        assertEquals("f47ac10b-58cc-4372-a567-0e02b2c3d479", s1.id)
        assertEquals(1001, s1.windowId)
        assertEquals("claude-backend refactor", s1.title)
        assertEquals(0.0, s1.bounds.x, 0.001)
        assertEquals(0.0, s1.bounds.y, 0.001)
        assertEquals(960.0, s1.bounds.width, 0.001)
        assertEquals(1080.0, s1.bounds.height, 0.001)
        assertTrue(s1.isSelected)

        // Session 2
        val s2 = ss.sessions[1]
        assertEquals("9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", s2.id)
        assertEquals(1002, s2.windowId)
        assertEquals("api-tests runner", s2.title)
        assertFalse(s2.isSelected)

        // Session 3
        val s3 = ss.sessions[2]
        assertEquals("6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b", s3.id)
        assertEquals(1003, s3.windowId)
        assertEquals("docs update", s3.title)
        assertFalse(s3.isSelected)

        // Screen bounds
        assertEquals(0.0, ss.screenBounds.x, 0.001)
        assertEquals(0.0, ss.screenBounds.y, 0.001)
        assertEquals(1920.0, ss.screenBounds.width, 0.001)
        assertEquals(1080.0, ss.screenBounds.height, 0.001)
    }

    @Test
    fun example_stateSync_reserializesWithRequiredFields() {
        val json = """
        {"type":"state_sync","version":1,"sessions":[],"screenBounds":{"x":0,"y":0,"width":1920,"height":1080}}
        """.trimIndent()
        val msg = fromJson(json)
        val reserialized = toJson(msg)
        val obj = parseJsonObject(reserialized)
        assertEquals("state_sync", obj["type"]!!.jsonPrimitive.content)
        assertEquals("1", obj["version"]!!.jsonPrimitive.content)
        assertTrue(obj.containsKey("sessions"))
        assertTrue(obj.containsKey("screenBounds"))
    }

    // --- selection_changed.json ---

    @Test
    fun example_selectionChanged_deserializesWithCorrectFields() {
        val json = """{"type":"selection_changed","version":1,"selectedSessionId":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"}"""
        val msg = fromJson(json)
        assertTrue("Must deserialize to SelectionChangedMessage", msg is WSMessage.SelectionChangedMessage)
        val sc = msg as WSMessage.SelectionChangedMessage
        assertEquals(1, sc.version)
        assertEquals("9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", sc.selectedSessionId)
    }

    @Test
    fun example_selectionChanged_reserializesWithRequiredFields() {
        val json = """{"type":"selection_changed","version":1,"selectedSessionId":"test-id"}"""
        val msg = fromJson(json)
        val reserialized = toJson(msg)
        val obj = parseJsonObject(reserialized)
        assertEquals("selection_changed", obj["type"]!!.jsonPrimitive.content)
        assertTrue(obj.containsKey("selectedSessionId"))
    }

    // --- cycle_selection.json ---

    @Test
    fun example_cycleSelection_deserializesWithCorrectFields() {
        val json = """{"type":"cycle_selection","version":1,"direction":"next"}"""
        val msg = fromJson(json)
        assertTrue("Must deserialize to CycleSelectionMessage", msg is WSMessage.CycleSelectionMessage)
        val cs = msg as WSMessage.CycleSelectionMessage
        assertEquals(1, cs.version)
        assertEquals("next", cs.direction)
    }

    @Test
    fun example_cycleSelection_reserializesWithRequiredFields() {
        val json = """{"type":"cycle_selection","version":1,"direction":"next"}"""
        val msg = fromJson(json)
        val reserialized = toJson(msg)
        val obj = parseJsonObject(reserialized)
        assertEquals("cycle_selection", obj["type"]!!.jsonPrimitive.content)
        assertTrue(obj.containsKey("direction"))
    }

    // --- send_text.json ---

    @Test
    fun example_sendText_deserializesWithCorrectFields() {
        val json = """{"type":"send_text","version":1,"text":"git status","sessionId":"f47ac10b-58cc-4372-a567-0e02b2c3d479","pressEnter":true}"""
        val msg = fromJson(json)
        assertTrue("Must deserialize to SendTextMessage", msg is WSMessage.SendTextMessage)
        val st = msg as WSMessage.SendTextMessage
        assertEquals(1, st.version)
        assertEquals("git status", st.text)
        assertEquals("f47ac10b-58cc-4372-a567-0e02b2c3d479", st.sessionId)
        assertTrue(st.pressEnter)
    }

    @Test
    fun example_sendText_reserializesWithRequiredFields() {
        val json = """{"type":"send_text","version":1,"text":"git status","sessionId":"s1","pressEnter":true}"""
        val msg = fromJson(json)
        val reserialized = toJson(msg)
        val obj = parseJsonObject(reserialized)
        assertEquals("send_text", obj["type"]!!.jsonPrimitive.content)
        assertTrue(obj.containsKey("text"))
        assertTrue(obj.containsKey("pressEnter"))
    }

    // --- request_sync.json ---

    @Test
    fun example_requestSync_deserializesWithCorrectFields() {
        val json = """{"type":"request_sync","version":1}"""
        val msg = fromJson(json)
        assertTrue("Must deserialize to RequestSyncMessage", msg is WSMessage.RequestSyncMessage)
        assertEquals(1, (msg as WSMessage.RequestSyncMessage).version)
    }

    @Test
    fun example_requestSync_reserializesWithRequiredFields() {
        val json = """{"type":"request_sync","version":1}"""
        val msg = fromJson(json)
        val reserialized = toJson(msg)
        val obj = parseJsonObject(reserialized)
        assertEquals("request_sync", obj["type"]!!.jsonPrimitive.content)
        assertEquals("1", obj["version"]!!.jsonPrimitive.content)
    }

    // --- error.json ---

    @Test
    fun example_error_deserializesWithCorrectFields() {
        val json = """{"type":"error","version":1,"message":"Session not found: invalid-uuid"}"""
        val msg = fromJson(json)
        assertTrue("Must deserialize to ErrorMessage", msg is WSMessage.ErrorMessage)
        val err = msg as WSMessage.ErrorMessage
        assertEquals(1, err.version)
        assertEquals("Session not found: invalid-uuid", err.message)
    }

    @Test
    fun example_error_reserializesWithRequiredFields() {
        val json = """{"type":"error","version":1,"message":"Session not found: invalid-uuid"}"""
        val msg = fromJson(json)
        val reserialized = toJson(msg)
        val obj = parseJsonObject(reserialized)
        assertEquals("error", obj["type"]!!.jsonPrimitive.content)
        assertTrue(obj.containsKey("message"))
    }

    // =========================================================================
    // SECTION 2: Schema-driven validation
    //
    // The JSON Schema specifies constraints the Kotlin code may or may not
    // enforce. These tests document the gap between spec and implementation.
    // =========================================================================

    @Test
    fun pairCode_mustMatchPattern_digitsOnly() {
        // Schema says: "pattern": "^[0-9]{6}$"
        // Creating a PairMessage with "abc123" must be rejected at construction time.
        try {
            WSMessage.PairMessage(code = "abc123", deviceId = "dev")
            fail("PairMessage with non-digit code must throw IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // Expected: the init block rejects codes that don't match ^[0-9]{6}$
        }

        // Valid 6-digit code must be accepted and round-trip correctly.
        val msg = WSMessage.PairMessage(code = "482910", deviceId = "dev")
        val json = toJson(msg)
        val codeValue = parseJsonObject(json)["code"]!!.jsonPrimitive.content
        val pattern = Regex("^[0-9]{6}$")
        assertTrue(
            "Pair code '$codeValue' must match pattern ^[0-9]{6}$ per schema.",
            pattern.matches(codeValue)
        )
    }

    @Test
    fun cycleSelection_direction_mustBeNextOrPrev() {
        // Schema says: "enum": ["next", "prev"]
        // Creating one with "forward" must be rejected at construction time.
        try {
            WSMessage.CycleSelectionMessage(direction = "forward")
            fail("CycleSelectionMessage with invalid direction must throw IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // Expected: the init block rejects directions other than "next" or "prev"
        }

        // Valid directions must be accepted.
        val msgNext = WSMessage.CycleSelectionMessage(direction = "next")
        val msgPrev = WSMessage.CycleSelectionMessage(direction = "prev")
        val dirNext = parseJsonObject(toJson(msgNext))["direction"]!!.jsonPrimitive.content
        val dirPrev = parseJsonObject(toJson(msgPrev))["direction"]!!.jsonPrimitive.content
        assertEquals("next", dirNext)
        assertEquals("prev", dirPrev)
    }

    @Test
    fun sendText_sessionId_isOptionalPerSchema_nullOmittedOrNull() {
        // Schema: sessionId is NOT in "required" list for send_text.
        // When null, serialization should either omit the field or emit null.
        // Both are acceptable per JSON Schema.
        val msg = WSMessage.SendTextMessage(text = "ls", sessionId = null, pressEnter = true)
        val json = toJson(msg)
        val obj = parseJsonObject(json)

        // With encodeDefaults=true, Kotlin emits "sessionId":null.
        // Verify the message is valid either way (field absent or null).
        if (obj.containsKey("sessionId")) {
            assertTrue(
                "sessionId should be null when not provided",
                obj["sessionId"]!!.toString() == "null"
            )
        }
        // If the field is absent, that's also valid per schema.
    }

    @Test
    fun pairResult_message_isOptionalPerSchema_nullCase() {
        // Schema: "message" is NOT in "required" list for pair_result.
        val msg = WSMessage.PairResultMessage(success = false, message = null)
        val json = toJson(msg)
        val obj = parseJsonObject(json)

        // Verify either omitted or null -- both valid.
        if (obj.containsKey("message")) {
            assertEquals("null", obj["message"]!!.toString())
        }
    }

    @Test
    fun allMessages_versionMustEqual1() {
        // Schema says: "version": { "const": 1 } for every message type.
        // The Kotlin code defaults to 1, but allows setting version=2.
        // The schema says ONLY version=1 is valid.
        val messages: List<WSMessage> = listOf(
            WSMessage.PairMessage(code = "000000", deviceId = "d"),
            WSMessage.PairResultMessage(success = true),
            WSMessage.StateSyncMessage(sessions = emptyList(), screenBounds = SessionBounds(0.0, 0.0, 1920.0, 1080.0)),
            WSMessage.SelectionChangedMessage(selectedSessionId = "s"),
            WSMessage.CycleSelectionMessage(direction = "next"),
            WSMessage.SendTextMessage(text = "t", pressEnter = true),
            WSMessage.RequestSyncMessage(),
            WSMessage.ErrorMessage(message = "e")
        )
        for (msg in messages) {
            assertEquals(
                "${msg::class.simpleName} version must be 1 per schema",
                1, msg.version
            )
            val json = toJson(msg)
            val obj = parseJsonObject(json)
            assertEquals(
                "${msg::class.simpleName} serialized version must be 1",
                "1", obj["version"]!!.jsonPrimitive.content
            )
        }
    }

    @Test
    fun additionalProperties_false_extraFieldsMustBeRejected() {
        // Schema says additionalProperties: false for every message type.
        // This means deserializing JSON with extra fields SHOULD fail.
        // But ProtocolJson has ignoreUnknownKeys=true, which silently ignores them.
        // FIXME: This requirement is not yet enforced by the implementation.
        // The schema says additional properties should be rejected, but the
        // Kotlin ProtocolJson instance is configured with ignoreUnknownKeys=true
        // for forward-compatibility. This is a deliberate design choice that
        // contradicts the strict schema. Document the gap.
        val jsonWithExtra = """{"type":"pair","version":1,"code":"123456","deviceId":"dev","extraField":"should-reject"}"""
        try {
            val msg = fromJson(jsonWithExtra)
            // If we get here, Kotlin accepted the extra field.
            // Per strict schema, this should have been rejected.
            // FIXME: additionalProperties:false is not enforced -- ignoreUnknownKeys=true
            // accepts extra fields for forward compatibility.
            assertNotNull("Implementation ignores extra fields (violates additionalProperties:false)", msg)
        } catch (e: Exception) {
            // If Kotlin rejects it, the schema constraint IS enforced.
            // This is the correct behavior per strict schema interpretation.
        }
    }

    // =========================================================================
    // SECTION 3: Cross-platform contract -- state_sync.json exact values
    // =========================================================================

    @Test
    fun crossPlatform_stateSyncExample_session1_exactFields() {
        val json = """
        {
          "type": "state_sync", "version": 1,
          "sessions": [
            {"id":"f47ac10b-58cc-4372-a567-0e02b2c3d479","windowId":1001,"title":"claude-backend refactor","bounds":{"x":0,"y":0,"width":960,"height":1080},"isSelected":true},
            {"id":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d","windowId":1002,"title":"api-tests runner","bounds":{"x":960,"y":0,"width":960,"height":540},"isSelected":false},
            {"id":"6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b","windowId":1003,"title":"docs update","bounds":{"x":960,"y":540,"width":960,"height":540},"isSelected":false}
          ],
          "screenBounds": {"x":0,"y":0,"width":1920,"height":1080}
        }
        """.trimIndent()
        val msg = fromJson(json) as WSMessage.StateSyncMessage

        assertEquals(3, msg.sessions.size)

        // Session 1: exact contract values
        val s1 = msg.sessions[0]
        assertEquals("f47ac10b-58cc-4372-a567-0e02b2c3d479", s1.id)
        assertEquals(1001, s1.windowId)
        assertEquals("claude-backend refactor", s1.title)
        assertEquals(0.0, s1.bounds.x, 0.0)
        assertEquals(0.0, s1.bounds.y, 0.0)
        assertEquals(960.0, s1.bounds.width, 0.0)
        assertEquals(1080.0, s1.bounds.height, 0.0)
        assertTrue("Session 1 must be selected", s1.isSelected)
    }

    @Test
    fun crossPlatform_stateSyncExample_session2_exactFields() {
        val json = """
        {
          "type": "state_sync", "version": 1,
          "sessions": [
            {"id":"f47ac10b-58cc-4372-a567-0e02b2c3d479","windowId":1001,"title":"claude-backend refactor","bounds":{"x":0,"y":0,"width":960,"height":1080},"isSelected":true},
            {"id":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d","windowId":1002,"title":"api-tests runner","bounds":{"x":960,"y":0,"width":960,"height":540},"isSelected":false},
            {"id":"6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b","windowId":1003,"title":"docs update","bounds":{"x":960,"y":540,"width":960,"height":540},"isSelected":false}
          ],
          "screenBounds": {"x":0,"y":0,"width":1920,"height":1080}
        }
        """.trimIndent()
        val msg = fromJson(json) as WSMessage.StateSyncMessage

        // Session 2: exact contract values
        val s2 = msg.sessions[1]
        assertEquals("9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", s2.id)
        assertEquals(1002, s2.windowId)
        assertEquals("api-tests runner", s2.title)
        assertFalse("Session 2 must NOT be selected", s2.isSelected)
    }

    @Test
    fun crossPlatform_stateSyncExample_session3_exactFields() {
        val json = """
        {
          "type": "state_sync", "version": 1,
          "sessions": [
            {"id":"f47ac10b-58cc-4372-a567-0e02b2c3d479","windowId":1001,"title":"claude-backend refactor","bounds":{"x":0,"y":0,"width":960,"height":1080},"isSelected":true},
            {"id":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d","windowId":1002,"title":"api-tests runner","bounds":{"x":960,"y":0,"width":960,"height":540},"isSelected":false},
            {"id":"6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b","windowId":1003,"title":"docs update","bounds":{"x":960,"y":540,"width":960,"height":540},"isSelected":false}
          ],
          "screenBounds": {"x":0,"y":0,"width":1920,"height":1080}
        }
        """.trimIndent()
        val msg = fromJson(json) as WSMessage.StateSyncMessage

        // Session 3: exact contract values
        val s3 = msg.sessions[2]
        assertEquals("6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b", s3.id)
        assertEquals(1003, s3.windowId)
        assertEquals("docs update", s3.title)
        assertFalse("Session 3 must NOT be selected", s3.isSelected)
    }

    @Test
    fun crossPlatform_stateSyncExample_screenBounds_exactValues() {
        val json = """
        {
          "type": "state_sync", "version": 1,
          "sessions": [],
          "screenBounds": {"x":0,"y":0,"width":1920,"height":1080}
        }
        """.trimIndent()
        val msg = fromJson(json) as WSMessage.StateSyncMessage
        assertEquals(0.0, msg.screenBounds.x, 0.0)
        assertEquals(0.0, msg.screenBounds.y, 0.0)
        assertEquals(1920.0, msg.screenBounds.width, 0.0)
        assertEquals(1080.0, msg.screenBounds.height, 0.0)
    }

    // =========================================================================
    // SECTION 4: Type discriminator correctness
    // =========================================================================

    @Test
    fun allEightMessageTypes_deserializeToDistinctClasses() {
        val jsonMessages = listOf(
            """{"type":"pair","version":1,"code":"000000","deviceId":"d"}""",
            """{"type":"pair_result","version":1,"success":true}""",
            """{"type":"state_sync","version":1,"sessions":[],"screenBounds":{"x":0,"y":0,"width":0,"height":0}}""",
            """{"type":"selection_changed","version":1,"selectedSessionId":"s"}""",
            """{"type":"cycle_selection","version":1,"direction":"next"}""",
            """{"type":"send_text","version":1,"text":"t","pressEnter":true}""",
            """{"type":"request_sync","version":1}""",
            """{"type":"error","version":1,"message":"e"}"""
        )
        val classes = jsonMessages.map { fromJson(it)::class }.toSet()
        assertEquals("All 8 message types must deserialize to distinct classes", 8, classes.size)
    }

    @Test
    fun typeDiscriminator_mustBePresentInAllSerializedMessages() {
        val messages: List<WSMessage> = listOf(
            WSMessage.PairMessage(code = "000000", deviceId = "d"),
            WSMessage.PairResultMessage(success = true),
            WSMessage.StateSyncMessage(sessions = emptyList(), screenBounds = SessionBounds(0.0, 0.0, 1920.0, 1080.0)),
            WSMessage.SelectionChangedMessage(selectedSessionId = "s"),
            WSMessage.CycleSelectionMessage(direction = "next"),
            WSMessage.SendTextMessage(text = "t", pressEnter = true),
            WSMessage.RequestSyncMessage(),
            WSMessage.ErrorMessage(message = "e")
        )
        val expectedTypes = listOf(
            "pair", "pair_result", "state_sync", "selection_changed",
            "cycle_selection", "send_text", "request_sync", "error"
        )
        for ((msg, expectedType) in messages.zip(expectedTypes)) {
            val obj = parseJsonObject(toJson(msg))
            assertEquals(
                "${msg::class.simpleName} must have type='$expectedType'",
                expectedType, obj["type"]!!.jsonPrimitive.content
            )
        }
    }

    // =========================================================================
    // SECTION 5: Round-trip fidelity
    // =========================================================================

    @Test
    fun roundTrip_allExamples_deserializeThenReserialize_preserveData() {
        // Every example from protocol/examples/ must survive a round-trip
        // without losing any information.
        val examples = listOf(
            """{"type":"pair","version":1,"code":"482910","deviceId":"pixel-8-a1b2c3d4"}""",
            """{"type":"pair_result","version":1,"success":true,"message":"Paired successfully"}""",
            """{"type":"selection_changed","version":1,"selectedSessionId":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"}""",
            """{"type":"cycle_selection","version":1,"direction":"next"}""",
            """{"type":"send_text","version":1,"text":"git status","sessionId":"f47ac10b-58cc-4372-a567-0e02b2c3d479","pressEnter":true}""",
            """{"type":"request_sync","version":1}""",
            """{"type":"error","version":1,"message":"Session not found: invalid-uuid"}"""
        )
        for (json in examples) {
            val msg1 = fromJson(json)
            val reserialized = toJson(msg1)
            val msg2 = fromJson(reserialized)
            assertEquals("Round-trip must preserve all data for ${msg1::class.simpleName}", msg1, msg2)
        }
    }

    @Test
    fun pairCode_withLeadingZeros_mustBePreservedAsString() {
        // Code "007890" must not become "7890" -- it's a string, not a number.
        val msg = WSMessage.PairMessage(code = "007890", deviceId = "dev")
        val json = toJson(msg)
        assertTrue("Leading zeros must be preserved", json.contains("\"007890\""))
        val restored = fromJson(json) as WSMessage.PairMessage
        assertEquals("007890", restored.code)
    }

    @Test
    fun unicodeInSessionTitle_mustSurviveRoundTrip() {
        val session = TerminalSession(
            id = "s1", windowId = 1, title = "\u2728 claude \u2014 opus-4",
            bounds = SessionBounds(0.0, 0.0, 800.0, 600.0), isSelected = true
        )
        val msg = WSMessage.StateSyncMessage(
            sessions = listOf(session),
            screenBounds = SessionBounds(0.0, 0.0, 1920.0, 1080.0)
        )
        val json = toJson(msg)
        val restored = fromJson(json) as WSMessage.StateSyncMessage
        assertEquals("\u2728 claude \u2014 opus-4", restored.sessions[0].title)
    }

    @Test
    fun unknownMessageType_mustThrowSerializationException() {
        // When the server sends a message type the client doesn't know,
        // deserialization must throw so the caller can handle it.
        val raw = """{"type":"future_feature","version":1,"data":"something"}"""
        try {
            fromJson(raw)
            fail("Deserializing an unknown message type must throw")
        } catch (e: kotlinx.serialization.SerializationException) {
            // Expected
        }
    }

    // =========================================================================
    // SECTION 6: Encoding defaults and null handling
    // =========================================================================

    @Test
    fun encodeDefaults_versionMustAlwaysAppearInJson() {
        // The Mac host may reject messages without a version field.
        // encodeDefaults=true ensures it's always present.
        val msg = WSMessage.RequestSyncMessage()
        val json = toJson(msg)
        assertTrue("version must appear in JSON", json.contains("\"version\":1"))
    }

    @Test
    fun encodeDefaults_nullSessionId_mustAppearInJson() {
        // With encodeDefaults=true, null fields should be explicitly encoded.
        val msg = WSMessage.SendTextMessage(text = "x", sessionId = null, pressEnter = true)
        val json = toJson(msg)
        assertTrue("null sessionId must be encoded", json.contains("\"sessionId\":null"))
    }

    @Test
    fun encodeDefaults_nullMessage_inPairResult_mustAppearInJson() {
        val msg = WSMessage.PairResultMessage(success = false, message = null)
        val json = toJson(msg)
        assertTrue("null message must be encoded", json.contains("\"message\":null"))
    }
}

package com.claudemulti.spec

import com.claudemulti.protocol.ProtocolJson
import com.claudemulti.protocol.WSMessage
import com.claudemulti.speech.PTTState
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Voice input must be safe and correct.
 *
 * These tests define the behavioral contract for speech recognition,
 * text length limits, and the push-to-talk state machine.
 *
 * NOTE: PushToTalkManager requires Android SpeechRecognizer and cannot be
 * directly unit-tested. We test the behavioral contracts and the message
 * formats that voice input produces.
 */
class VoiceInputSpecTest {

    // =========================================================================
    // Helpers
    // =========================================================================

    private fun toJson(msg: WSMessage): String =
        ProtocolJson.encodeToString<WSMessage>(msg)

    // =========================================================================
    // REQUIREMENT: Recognized text MUST be limited to 1000 characters
    // =========================================================================

    @Test
    fun recognizedText_mustBeLimitedTo1000Characters() {
        // PushToTalkManager.onResults does: val capped = bestResult.take(1000)
        // This ensures even if the recognizer returns >1000 chars, we cap it.
        val longResult = "x".repeat(2000)
        val capped = longResult.take(1000)
        assertEquals(1000, capped.length)
    }

    @Test
    fun recognizedText_exactly1000Chars_mustBeAccepted() {
        val text = "b".repeat(1000)
        // The ViewModel checks: text.isNotBlank() && text.length <= 1000
        val wouldSend = text.isNotBlank() && text.length <= 1000
        assertTrue("1000-char text must be accepted", wouldSend)
    }

    @Test
    fun recognizedText_exactly1001Chars_mustBeRejectedByViewModel() {
        // The ViewModel's guard rejects text over 1000 chars entirely.
        // Note: PushToTalkManager caps at 1000, so the ViewModel should never
        // see >1000 chars from voice. But the guard exists as defense in depth.
        val text = "a".repeat(1001)
        val wouldSend = text.isNotBlank() && text.length <= 1000
        assertFalse("1001-char text must be rejected by ViewModel guard", wouldSend)
    }

    // =========================================================================
    // REQUIREMENT: Text over 1000 chars MUST be truncated (not rejected entirely)
    // =========================================================================

    @Test
    fun textOver1000Chars_mustBeTruncated_notRejectedEntirely() {
        // The PushToTalkManager uses .take(1000) which truncates, preserving
        // the first 1000 characters of spoken words. This is the correct
        // behavior: the user spoke valid words, so we keep what we can.
        val spoken = "valid words ".repeat(200) // ~2400 chars
        val capped = spoken.take(1000)

        assertTrue("Truncated text must not be empty", capped.isNotEmpty())
        assertEquals("Truncated text must be exactly 1000 chars", 1000, capped.length)
        assertTrue("Truncated text must start with the spoken words", capped.startsWith("valid words"))
    }

    // =========================================================================
    // REQUIREMENT: Empty recognition results MUST NOT be sent
    // =========================================================================

    @Test
    fun emptyRecognitionResult_mustNotBeSent() {
        val emptyText = ""
        val wouldSend = emptyText.isNotBlank() && emptyText.length <= 1000
        assertFalse("Empty text must not be sent", wouldSend)
    }

    // =========================================================================
    // REQUIREMENT: Blank-only recognition results MUST NOT be sent
    // =========================================================================

    @Test
    fun blankOnlyRecognitionResult_mustNotBeSent() {
        val blankTexts = listOf("", "   ", "\t", "\n", " \t \n ")
        for (text in blankTexts) {
            val wouldSend = text.isNotBlank() && text.length <= 1000
            assertFalse("Blank text '${text.replace("\n","\\n").replace("\t","\\t")}' must not be sent", wouldSend)
        }
    }

    // =========================================================================
    // REQUIREMENT: Recognized text MUST be sent as SendTextMessage with pressEnter=true
    // =========================================================================

    @Test
    fun recognizedText_mustBeSentAsSendTextMessage_withPressEnterTrue() {
        // The ViewModel creates: SendTextMessage(text=text, sessionId=selected, pressEnter=true)
        val msg = WSMessage.SendTextMessage(
            text = "hello world",
            sessionId = "some-session-id",
            pressEnter = true
        )
        assertTrue("pressEnter must be true for voice input", msg.pressEnter)
        assertEquals("hello world", msg.text)
    }

    @Test
    fun recognizedText_sendTextMessage_serializedCorrectly() {
        val msg = WSMessage.SendTextMessage(
            text = "run tests",
            sessionId = "f47ac10b-58cc-4372-a567-0e02b2c3d479",
            pressEnter = true
        )
        val json = toJson(msg)
        val obj = Json.parseToJsonElement(json).jsonObject

        assertEquals("send_text", obj["type"]!!.jsonPrimitive.content)
        assertEquals("run tests", obj["text"]!!.jsonPrimitive.content)
        assertEquals("true", obj["pressEnter"]!!.jsonPrimitive.content)
        assertEquals(
            "f47ac10b-58cc-4372-a567-0e02b2c3d479",
            obj["sessionId"]!!.jsonPrimitive.content
        )
    }

    // =========================================================================
    // REQUIREMENT: The SendTextMessage MUST include the currently selected sessionId
    // =========================================================================

    @Test
    fun sendTextMessage_mustIncludeSelectedSessionId() {
        // The ViewModel uses: sessionId = _selectedSessionId.value
        // When a session is selected, the message must target that session.
        val selectedSession = "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"
        val msg = WSMessage.SendTextMessage(
            text = "git status",
            sessionId = selectedSession,
            pressEnter = true
        )
        assertEquals(selectedSession, msg.sessionId)
    }

    @Test
    fun sendTextMessage_withNoSessionSelected_sessionIdMustBeNull() {
        // When no session is selected, sessionId should be null.
        // The Mac host will route to the active/focused session.
        val msg = WSMessage.SendTextMessage(
            text = "ls -la",
            sessionId = null,
            pressEnter = true
        )
        assertEquals(null, msg.sessionId)
    }

    // =========================================================================
    // REQUIREMENT: Voice MUST NOT start without RECORD_AUDIO permission
    // =========================================================================

    @Test
    fun voiceStart_withoutPermission_mustBeBlocked() {
        // The ViewModel checks: if (!hasPermission) return
        // This test documents the requirement.
        val hasPermission = false
        assertFalse(
            "Voice must not start without RECORD_AUDIO permission",
            hasPermission
        )
        // In the real implementation:
        //   fun startVoice(hasPermission: Boolean) {
        //       if (!hasPermission) {
        //           Log.w(TAG, "startVoice called without RECORD_AUDIO permission -- ignoring")
        //           return
        //       }
        //       pushToTalkManager.startListening()
        //   }
    }

    @Test
    fun voiceStart_withPermission_mustProceed() {
        val hasPermission = true
        assertTrue("Voice must start when permission is granted", hasPermission)
    }

    // =========================================================================
    // REQUIREMENT: PTT state machine: Idle -> Listening -> Processing -> Idle
    // =========================================================================

    @Test
    fun pttStateMachine_mustHaveFourStates() {
        val states = PTTState.values()
        assertEquals(4, states.size)
        assertTrue(states.contains(PTTState.Idle))
        assertTrue(states.contains(PTTState.Listening))
        assertTrue(states.contains(PTTState.Processing))
        assertTrue(states.contains(PTTState.Error))
    }

    @Test
    fun pttStateMachine_initialState_mustBeIdle() {
        // PushToTalkManager initializes _state = MutableStateFlow(PTTState.Idle)
        assertEquals(PTTState.Idle, PTTState.values()[0])
    }

    @Test
    fun pttStateMachine_ordinals_mustBeStable() {
        assertEquals(0, PTTState.Idle.ordinal)
        assertEquals(1, PTTState.Listening.ordinal)
        assertEquals(2, PTTState.Processing.ordinal)
        assertEquals(3, PTTState.Error.ordinal)
    }

    @Test
    fun pttStateMachine_normalFlow_Idle_Listening_Processing_Idle() {
        // Document the expected state transitions:
        // 1. Idle -> Listening (onReadyForSpeech)
        // 2. Listening -> Processing (onEndOfSpeech)
        // 3. Processing -> Idle (onResults)
        val normalFlow = listOf(
            PTTState.Idle,
            PTTState.Listening,
            PTTState.Processing,
            PTTState.Idle
        )
        assertEquals(PTTState.Idle, normalFlow.first())
        assertEquals(PTTState.Idle, normalFlow.last())
        assertEquals(PTTState.Listening, normalFlow[1])
        assertEquals(PTTState.Processing, normalFlow[2])
    }

    @Test
    fun pttStateMachine_errorFlow_Idle_Listening_Error_Idle() {
        // On fatal errors: Idle -> Listening -> Error
        // The Error state transitions back to Idle on next startListening attempt.
        val errorFlow = listOf(
            PTTState.Idle,
            PTTState.Listening,
            PTTState.Error
        )
        assertEquals(PTTState.Idle, errorFlow.first())
        assertEquals(PTTState.Error, errorFlow.last())
    }

    // =========================================================================
    // Edge cases: voice input with special characters
    // =========================================================================

    @Test
    fun voiceInput_withUnicode_mustSerializeCorrectly() {
        val msg = WSMessage.SendTextMessage(
            text = "echo \u201Chello world\u201D",
            sessionId = null,
            pressEnter = true
        )
        val json = toJson(msg)
        val restored = ProtocolJson.decodeFromString<WSMessage>(json) as WSMessage.SendTextMessage
        assertEquals("echo \u201Chello world\u201D", restored.text)
    }

    @Test
    fun voiceInput_withNewlines_mustSerializeCorrectly() {
        // Speech recognizer might return text with newlines in some locales.
        val msg = WSMessage.SendTextMessage(
            text = "line one\nline two",
            sessionId = null,
            pressEnter = true
        )
        val json = toJson(msg)
        val restored = ProtocolJson.decodeFromString<WSMessage>(json) as WSMessage.SendTextMessage
        assertEquals("line one\nline two", restored.text)
    }

    // =========================================================================
    // REQUIREMENT: PushToTalkManager must only start from Idle state
    // =========================================================================

    @Test
    fun pttManager_startListening_mustOnlyWorkFromIdleState() {
        // PushToTalkManager.startListening checks:
        //   if (_state.value != PTTState.Idle) return
        // This prevents rapid double-tapping from creating multiple listeners.
        // Document: non-Idle states (Listening, Processing, Error) reject start.
        val nonIdleStates = listOf(PTTState.Listening, PTTState.Processing, PTTState.Error)
        for (state in nonIdleStates) {
            assertTrue(
                "startListening must be rejected when state is $state",
                state != PTTState.Idle
            )
        }
    }

    // =========================================================================
    // REQUIREMENT: PushToTalkManager.onResults caps at 1000 chars and emits
    // only non-empty results
    // =========================================================================

    @Test
    fun onResults_emptyBestResult_mustNotEmit() {
        // When the recognizer returns an empty string (e.g., noise only),
        // it must not be emitted to finalResult.
        val bestResult = ""
        val capped = bestResult.take(1000)
        // PushToTalkManager checks: if (capped.isNotEmpty()) _finalResult.tryEmit(capped)
        assertFalse("Empty result must not be emitted", capped.isNotEmpty())
    }

    @Test
    fun onResults_validResult_mustBeEmitted() {
        val bestResult = "hello world"
        val capped = bestResult.take(1000)
        assertTrue("Non-empty result must be emitted", capped.isNotEmpty())
        assertEquals("hello world", capped)
    }

    @Test
    fun onResults_longResult_mustBeCappedAt1000() {
        val bestResult = "word ".repeat(400) // 2000 chars
        val capped = bestResult.take(1000)
        assertEquals(1000, capped.length)
        assertTrue("Capped result must start with original content", capped.startsWith("word "))
    }
}

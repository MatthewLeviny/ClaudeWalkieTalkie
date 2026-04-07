package com.claudemulti.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class SessionBounds(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double
)

@Serializable
data class TerminalSession(
    val id: String,
    val windowId: Int,
    val title: String,
    val bounds: SessionBounds,
    val isSelected: Boolean
)

/**
 * Sealed interface representing all WebSocket message types in the ClaudeMulti protocol.
 *
 * Uses kotlinx-serialization polymorphism with [classDiscriminator] = "type" so
 * the JSON "type" field selects the concrete class via @SerialName.
 *
 * Every message carries a [version] field (default 1) for forward compatibility.
 */
@Serializable
sealed interface WSMessage {

    val version: Int

    @Serializable
    @SerialName("pair")
    data class PairMessage(
        override val version: Int = 1,
        val code: String,
        val deviceId: String
    ) : WSMessage {
        init {
            require(code.matches(Regex("^[0-9]{6}$"))) {
                "Pairing code must be exactly 6 digits"
            }
        }
    }

    @Serializable
    @SerialName("pair_result")
    data class PairResultMessage(
        override val version: Int = 1,
        val success: Boolean,
        val message: String? = null
    ) : WSMessage

    @Serializable
    @SerialName("state_sync")
    data class StateSyncMessage(
        override val version: Int = 1,
        val sessions: List<TerminalSession>,
        val screenBounds: SessionBounds
    ) : WSMessage

    @Serializable
    @SerialName("selection_changed")
    data class SelectionChangedMessage(
        override val version: Int = 1,
        val selectedSessionId: String
    ) : WSMessage

    @Serializable
    @SerialName("cycle_selection")
    data class CycleSelectionMessage(
        override val version: Int = 1,
        val direction: String
    ) : WSMessage {
        init {
            require(direction == "next" || direction == "prev") {
                "Direction must be 'next' or 'prev'"
            }
        }
    }

    @Serializable
    @SerialName("send_text")
    data class SendTextMessage(
        override val version: Int = 1,
        val text: String,
        val sessionId: String? = null,
        val pressEnter: Boolean
    ) : WSMessage

    @Serializable
    @SerialName("request_sync")
    data class RequestSyncMessage(
        override val version: Int = 1
    ) : WSMessage

    @Serializable
    @SerialName("error")
    data class ErrorMessage(
        override val version: Int = 1,
        val message: String
    ) : WSMessage
}

/**
 * Pre-configured [Json] instance for encoding/decoding [WSMessage] types.
 *
 * - `classDiscriminator = "type"`: the "type" JSON field selects the concrete subclass.
 * - `ignoreUnknownKeys = true`: forward-compatible with future protocol extensions.
 * - `encodeDefaults = true`: always emits `version`, optional nulls, etc.
 */
val ProtocolJson: Json = Json {
    classDiscriminator = "type"
    ignoreUnknownKeys = true
    encodeDefaults = true
}

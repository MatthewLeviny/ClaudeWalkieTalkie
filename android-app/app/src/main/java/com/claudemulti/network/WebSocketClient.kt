package com.claudemulti.network

import android.util.Log
import com.claudemulti.BuildConfig
import com.claudemulti.protocol.ProtocolJson
import com.claudemulti.protocol.TerminalSession
import com.claudemulti.protocol.WSMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

/**
 * Represents the lifecycle state of the WebSocket connection.
 */
enum class ConnectionState {
    /** No active connection. */
    Disconnected,
    /** TCP handshake / WebSocket upgrade in progress. */
    Connecting,
    /** WebSocket open, but not yet paired with the Mac host. */
    Connected,
    /** Successfully paired -- ready for message exchange. */
    Paired
}

/**
 * Manages the WebSocket connection to a ClaudeMulti Mac host.
 *
 * Provides reactive [StateFlow]s for connection state, terminal sessions,
 * and the currently selected session, plus a [SharedFlow] that emits every
 * inbound [WSMessage].
 *
 * Reconnection uses exponential back-off (1 s .. 30 s, up to 10 attempts).
 */
class WebSocketClient {

    companion object {
        private const val TAG = "WebSocketClient"
        private const val MAX_RECONNECT_ATTEMPTS = 10
        private const val BASE_RECONNECT_DELAY_MS = 1_000L
        private const val MAX_RECONNECT_DELAY_MS = 30_000L
        private const val CLOSE_NORMAL = 1000
        private const val MAX_MESSAGE_SIZE = 100_000 // 100KB
    }

    // --------------- coroutine scope ---------------

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // --------------- OkHttp ---------------

    private val client: OkHttpClient = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)   // no read timeout for long-lived WS
        .pingInterval(30, TimeUnit.SECONDS)       // keep-alive pings
        .build()

    private var webSocket: WebSocket? = null
    private var currentHost: String? = null
    private var currentPort: Int? = null

    // --------------- public reactive state ---------------

    private val _connectionState = MutableStateFlow(ConnectionState.Disconnected)
    /** Current connection lifecycle state. */
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _messages = MutableSharedFlow<WSMessage>(
        replay = 0,
        extraBufferCapacity = 64
    )
    /** Every inbound message, regardless of type. */
    val messages: SharedFlow<WSMessage> = _messages.asSharedFlow()

    private val _sessions = MutableStateFlow<List<TerminalSession>>(emptyList())
    /** Terminal sessions from the most recent [WSMessage.StateSyncMessage]. */
    val sessions: StateFlow<List<TerminalSession>> = _sessions.asStateFlow()

    private val _selectedSessionId = MutableStateFlow<String?>(null)
    /** ID of the currently selected session on the Mac host. */
    val selectedSessionId: StateFlow<String?> = _selectedSessionId.asStateFlow()

    private val _isStale = MutableStateFlow(false)
    /**
     * `true` when the connection has dropped but we are still showing last-known state.
     * The UI can use this to dim the display and show a "Reconnecting..." overlay.
     */
    val isStale: StateFlow<Boolean> = _isStale.asStateFlow()

    private val _connectionError = MutableStateFlow<String?>(null)
    /** The last connection error message, or null if no error. */
    val connectionError: StateFlow<String?> = _connectionError.asStateFlow()

    // --------------- auth token for reconnection ---------------

    /** Auth token received from the server after pairing. Sent as a header on reconnect. */
    var authToken: String? = null

    // --------------- reconnection bookkeeping ---------------

    private var reconnectAttempt = 0
    @Volatile
    private var shouldReconnect = true

    /**
     * Tracks whether we have been paired before in this session.
     * Used to auto-send RequestSync and re-pair on reconnection.
     */
    @Volatile
    private var wasPreviouslyPaired = false

    // --------------- public API ---------------

    /**
     * Open a WebSocket to [host]:[port].
     *
     * Any existing connection is closed first. Reconnection attempts are reset.
     */
    fun connect(host: String, port: Int) {
        // Tear down any previous socket without triggering reconnect
        webSocket?.close(CLOSE_NORMAL, "Reconnecting to new host")
        webSocket = null

        currentHost = host
        currentPort = port
        reconnectAttempt = 0
        shouldReconnect = true
        _connectionError.value = null
        doConnect(host, port)
    }

    /**
     * Gracefully close the connection. No automatic reconnect will occur.
     */
    fun disconnect() {
        shouldReconnect = false
        wasPreviouslyPaired = false
        authToken = null
        reconnectAttempt = MAX_RECONNECT_ATTEMPTS // prevent any in-flight reconnect
        webSocket?.close(CLOSE_NORMAL, "Client disconnecting")
        webSocket = null
        _connectionState.value = ConnectionState.Disconnected
        _isStale.value = false
        _connectionError.value = null
    }

    /**
     * Serialize [message] to JSON and send it over the WebSocket.
     *
     * Returns `true` if the message was enqueued successfully.
     */
    fun send(message: WSMessage): Boolean {
        val ws = webSocket ?: return false
        val json = ProtocolJson.encodeToString<WSMessage>(message)
        if (BuildConfig.DEBUG) Log.d(TAG, "TX: ${json.take(200)}")
        return ws.send(json)
    }

    /**
     * Convenience: send a [WSMessage.PairMessage] with the given [code] and [deviceId].
     */
    fun sendPair(code: String, deviceId: String) {
        send(WSMessage.PairMessage(code = code, deviceId = deviceId))
    }

    /**
     * Mark the connection as paired. Called by the ViewModel after receiving
     * a successful [WSMessage.PairResultMessage].
     */
    fun markPaired() {
        _connectionState.value = ConnectionState.Paired
        wasPreviouslyPaired = true
        _isStale.value = false
        _connectionError.value = null
    }

    /**
     * Returns the host and port of the current (or last attempted) connection,
     * or null if [connect] has never been called.
     */
    fun currentServer(): Pair<String, Int>? {
        val host = currentHost ?: return null
        val port = currentPort ?: return null
        return host to port
    }

    /**
     * Whether the client was previously paired in this session.
     * Useful for determining if we should attempt auto-reconnect on resume.
     */
    fun wasPaired(): Boolean = wasPreviouslyPaired

    /**
     * Cancel the internal coroutine scope. Call when the client will no longer
     * be used (e.g. ViewModel.onCleared).
     */
    fun destroy() {
        disconnect()
        scope.cancel()
    }

    // --------------- internal ---------------

    private fun doConnect(host: String, port: Int) {
        _connectionState.value = ConnectionState.Connecting
        _connectionError.value = null

        val requestBuilder = Request.Builder()
            .url("ws://$host:$port")

        // Include auth token header if available, so the server can identify
        // a previously paired client without requiring re-pairing.
        authToken?.let { token ->
            if (token.isNotEmpty()) {
                requestBuilder.addHeader("X-Auth-Token", token)
            }
        }

        webSocket = client.newWebSocket(requestBuilder.build(), Listener())
    }

    /**
     * Exponential back-off: delay = base * 2^attempt, capped at [MAX_RECONNECT_DELAY_MS].
     */
    private fun attemptReconnect() {
        if (!shouldReconnect) return
        val host = currentHost ?: return
        val port = currentPort ?: return

        if (reconnectAttempt >= MAX_RECONNECT_ATTEMPTS) {
            Log.w(TAG, "Reconnection attempts exhausted ($MAX_RECONNECT_ATTEMPTS)")
            _connectionError.value = "Could not reconnect after $MAX_RECONNECT_ATTEMPTS attempts"
            return
        }

        val attempt = reconnectAttempt
        reconnectAttempt++

        scope.launch {
            val delayMs = (BASE_RECONNECT_DELAY_MS * (1L shl attempt))
                .coerceAtMost(MAX_RECONNECT_DELAY_MS)
            Log.d(TAG, "Reconnecting in ${delayMs}ms (attempt ${attempt + 1}/$MAX_RECONNECT_ATTEMPTS)")
            delay(delayMs)
            if (shouldReconnect) {
                doConnect(host, port)
            }
        }
    }

    // --------------- WebSocketListener ---------------

    private inner class Listener : WebSocketListener() {

        override fun onOpen(webSocket: WebSocket, response: Response) {
            Log.i(TAG, "WebSocket opened: ${response.request.url}")
            _connectionState.value = ConnectionState.Connected
            _connectionError.value = null
            reconnectAttempt = 0

            // On reconnection after a previous pairing, automatically request
            // a fresh state sync so the UI gets up-to-date data.
            if (wasPreviouslyPaired) {
                Log.i(TAG, "Reconnected after previous pairing -- requesting sync")
                _connectionState.value = ConnectionState.Paired
                _isStale.value = false
                send(WSMessage.RequestSyncMessage())
            }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            if (text.length > MAX_MESSAGE_SIZE) {
                Log.e(TAG, "Message exceeds size limit (${text.length} > $MAX_MESSAGE_SIZE)")
                return
            }
            if (BuildConfig.DEBUG) Log.d(TAG, "RX: ${text.take(200)}")
            val message: WSMessage = try {
                ProtocolJson.decodeFromString<WSMessage>(text)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to deserialize message", e)
                return
            }

            // Emit on the shared flow for any subscriber
            _messages.tryEmit(message)

            // Derive convenience state from specific message types
            when (message) {
                is WSMessage.StateSyncMessage -> {
                    _sessions.value = message.sessions
                    _isStale.value = false
                    // Also derive the selected session from the sync
                    val selected = message.sessions.firstOrNull { it.isSelected }
                    if (selected != null) {
                        _selectedSessionId.value = selected.id
                    }
                }
                is WSMessage.SelectionChangedMessage -> {
                    _selectedSessionId.value = message.selectedSessionId
                }
                is WSMessage.PairResultMessage -> {
                    if (message.success) {
                        _connectionState.value = ConnectionState.Paired
                        wasPreviouslyPaired = true
                        _isStale.value = false
                    }
                }
                else -> { /* other message types are available via the messages flow */ }
            }
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            Log.d(TAG, "WebSocket closing: code=$code reason=$reason")
            webSocket.close(CLOSE_NORMAL, null)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            Log.i(TAG, "WebSocket closed: code=$code reason=$reason")
            // Keep last-known sessions/selectedSessionId (don't clear them) but mark stale
            if (_sessions.value.isNotEmpty()) {
                _isStale.value = true
            }
            _connectionState.value = ConnectionState.Disconnected
            attemptReconnect()
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            Log.e(TAG, "WebSocket failure: ${t.message}", t)
            // Keep last-known sessions/selectedSessionId (don't clear them) but mark stale
            if (_sessions.value.isNotEmpty()) {
                _isStale.value = true
            }
            _connectionState.value = ConnectionState.Disconnected
            _connectionError.value = t.message ?: "Connection failed"
            attemptReconnect()
        }
    }
}

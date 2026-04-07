package com.claudemulti.viewmodel

import android.app.Application
import android.content.Context
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.claudemulti.BuildConfig
import com.claudemulti.network.BonjourDiscovery
import com.claudemulti.network.ConnectionState
import com.claudemulti.network.ServerInfo
import com.claudemulti.network.WebSocketClient
import com.claudemulti.protocol.SessionBounds
import com.claudemulti.protocol.TerminalSession
import com.claudemulti.protocol.WSMessage
import com.claudemulti.speech.PTTState
import com.claudemulti.speech.PushToTalkManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/**
 * Persisted info about the last successfully connected server.
 */
data class LastServer(
    val host: String,
    val port: Int,
    val name: String
)

/**
 * Simple repository that handles last-server persistence via SharedPreferences.
 * Accepts a [Context] so the ViewModel itself does not need one.
 */
class PreferencesRepository(context: Context) {

    companion object {
        private const val PREFS_NAME = "claudemulti_secure_prefs"
        private const val PREF_LAST_HOST = "last_server_host"
        private const val PREF_LAST_PORT = "last_server_port"
        private const val PREF_LAST_NAME = "last_server_name"
        private const val PREF_DEVICE_ID = "device_id"
        private const val PREF_AUTH_TOKEN = "auth_token"
    }

    private val prefs = try {
        androidx.security.crypto.EncryptedSharedPreferences.create(
            PREFS_NAME,
            androidx.security.crypto.MasterKeys.getOrCreate(
                androidx.security.crypto.MasterKeys.AES256_GCM_SPEC
            ),
            context,
            androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (e: Exception) {
        // Fallback to regular prefs if encryption fails (e.g., no hardware keystore)
        android.util.Log.w("PreferencesRepository", "EncryptedSharedPreferences unavailable, using fallback", e)
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun saveLastServer(host: String, port: Int, name: String) {
        prefs.edit()
            .putString(PREF_LAST_HOST, host)
            .putInt(PREF_LAST_PORT, port)
            .putString(PREF_LAST_NAME, name)
            .apply()
    }

    fun restoreLastServer(): LastServer? {
        val host = prefs.getString(PREF_LAST_HOST, null) ?: return null
        val port = prefs.getInt(PREF_LAST_PORT, 0)
        val name = prefs.getString(PREF_LAST_NAME, "") ?: ""
        return if (port > 0) LastServer(host, port, name) else null
    }

    fun clearLastServer() {
        prefs.edit()
            .remove(PREF_LAST_HOST)
            .remove(PREF_LAST_PORT)
            .remove(PREF_LAST_NAME)
            .apply()
    }

    /**
     * Returns a stable, cryptographically random device ID.
     * Generated once via UUID and persisted in EncryptedSharedPreferences.
     */
    fun getOrCreateDeviceId(): String {
        val existing = prefs.getString(PREF_DEVICE_ID, null)
        if (existing != null) return existing
        val newId = java.util.UUID.randomUUID().toString()
        prefs.edit().putString(PREF_DEVICE_ID, newId).apply()
        return newId
    }

    fun saveAuthToken(token: String) {
        prefs.edit().putString(PREF_AUTH_TOKEN, token).apply()
    }

    fun getAuthToken(): String? {
        return prefs.getString(PREF_AUTH_TOKEN, null)
    }

    fun clearAuthToken() {
        prefs.edit().remove(PREF_AUTH_TOKEN).apply()
    }
}

class RemoteViewModel(
    private val webSocketClient: WebSocketClient,
    private val bonjourDiscovery: BonjourDiscovery,
    private val pushToTalkManager: PushToTalkManager,
    private val preferencesRepository: PreferencesRepository
) : ViewModel() {

    companion object {
        private const val TAG = "RemoteViewModel"
    }

    // --- Exposed state ---

    private val _sessions = MutableStateFlow<List<TerminalSession>>(emptyList())
    val sessions: StateFlow<List<TerminalSession>> = _sessions.asStateFlow()

    private val _selectedSessionId = MutableStateFlow<String?>(null)
    val selectedSessionId: StateFlow<String?> = _selectedSessionId.asStateFlow()

    private val _screenBounds = MutableStateFlow(SessionBounds(0.0, 0.0, 1920.0, 1080.0))
    val screenBounds: StateFlow<SessionBounds> = _screenBounds.asStateFlow()

    val connectionState: StateFlow<ConnectionState> = webSocketClient.connectionState

    val discoveredServers: StateFlow<List<ServerInfo>> = bonjourDiscovery.discoveredServers

    val pttState: StateFlow<PTTState> = pushToTalkManager.state

    val partialTranscription: StateFlow<String> = pushToTalkManager.partialResult

    val volumeInterceptionEnabled = MutableStateFlow(true)

    /** True when the displayed state may be outdated (connection dropped). */
    val isStale: StateFlow<Boolean> = webSocketClient.isStale

    /** The last connection error message, if any. */
    val connectionError: StateFlow<String?> = webSocketClient.connectionError

    private val _lastServer = MutableStateFlow<LastServer?>(null)
    /** The last successfully connected server, restored from SharedPreferences. */
    val lastServer: StateFlow<LastServer?> = _lastServer.asStateFlow()

    init {
        // Restore last server from preferences
        val restored = preferencesRepository.restoreLastServer()
        if (restored != null) {
            _lastServer.value = restored
            Log.d(TAG, "Restored last server: ${restored.host}:${restored.port} (${restored.name})")
        }

        // Restore auth token for reconnection
        webSocketClient.authToken = preferencesRepository.getAuthToken()

        // Start mDNS discovery automatically
        bonjourDiscovery.startDiscovery()

        // Observe incoming WebSocket messages
        webSocketClient.messages
            .onEach { handleMessage(it) }
            .launchIn(viewModelScope)

        // Forward recognized speech as send_text commands
        pushToTalkManager.finalResult
            .onEach { text ->
                if (text.isNotBlank() && text.length <= 1000) {
                    if (BuildConfig.DEBUG) Log.d(TAG, "Sending recognized text: \"$text\"")
                    webSocketClient.send(
                        WSMessage.SendTextMessage(
                            text = text,
                            sessionId = _selectedSessionId.value,
                            pressEnter = true
                        )
                    )
                }
            }
            .launchIn(viewModelScope)
    }

    // --- Public actions ---

    fun connect(host: String, port: Int) {
        webSocketClient.connect(host, port)
    }

    fun disconnect() {
        webSocketClient.disconnect()
        preferencesRepository.clearAuthToken()
        webSocketClient.authToken = null
        _sessions.value = emptyList()
        _selectedSessionId.value = null
    }

    fun sendPairingCode(code: String) {
        val deviceId = preferencesRepository.getOrCreateDeviceId()
        webSocketClient.send(
            WSMessage.PairMessage(code = code, deviceId = deviceId)
        )
    }

    fun cycleSelection(direction: String = "next") {
        webSocketClient.send(WSMessage.CycleSelectionMessage(direction = direction))
    }

    fun sendText(text: String) {
        webSocketClient.send(
            WSMessage.SendTextMessage(
                text = text,
                sessionId = _selectedSessionId.value,
                pressEnter = true
            )
        )
    }

    /**
     * Start voice recognition. Requires [hasPermission] to be true (RECORD_AUDIO granted).
     * If permission is not granted, the call is ignored and a warning is logged.
     */
    fun startVoice(hasPermission: Boolean) {
        if (!hasPermission) {
            Log.w(TAG, "startVoice called without RECORD_AUDIO permission — ignoring")
            return
        }
        pushToTalkManager.startListening()
    }

    fun stopVoice() {
        pushToTalkManager.stopListening()
    }

    fun startServerDiscovery() {
        bonjourDiscovery.startDiscovery()
    }

    fun stopServerDiscovery() {
        bonjourDiscovery.stopDiscovery()
    }

    fun requestSync() {
        webSocketClient.send(WSMessage.RequestSyncMessage())
    }

    /**
     * Called when the app returns to the foreground.
     * If we were previously paired but the connection dropped, attempt to reconnect.
     */
    fun onResume() {
        val state = webSocketClient.connectionState.value
        if (state == ConnectionState.Disconnected && webSocketClient.wasPaired()) {
            val server = webSocketClient.currentServer()
            if (server != null) {
                Log.i(TAG, "Resuming: reconnecting to ${server.first}:${server.second}")
                webSocketClient.connect(server.first, server.second)
            }
        }
    }

    /**
     * Called when the app goes to the background.
     * We keep the connection alive -- the WebSocket ping/pong will maintain it.
     */
    fun onPause() {
        // Intentionally keep the connection alive in the background.
        // OkHttp's ping interval (30s) will keep the socket from timing out.
        Log.d(TAG, "onPause: keeping WebSocket connection alive")
    }

    // --- Last server persistence ---

    private fun saveLastServer(host: String, port: Int, name: String) {
        preferencesRepository.saveLastServer(host, port, name)
        _lastServer.value = LastServer(host, port, name)
        Log.d(TAG, "Saved last server: $host:$port ($name)")
    }

    fun clearLastServer() {
        preferencesRepository.clearLastServer()
        _lastServer.value = null
    }

    // --- Message handling ---

    private fun handleMessage(message: WSMessage) {
        when (message) {
            is WSMessage.StateSyncMessage -> {
                _sessions.value = message.sessions
                _screenBounds.value = message.screenBounds

                // Update selected session: keep current if still valid, else pick first selected
                val currentId = _selectedSessionId.value
                val stillValid = message.sessions.any { it.id == currentId }
                if (!stillValid) {
                    _selectedSessionId.value = message.sessions
                        .firstOrNull { it.isSelected }?.id
                        ?: message.sessions.firstOrNull()?.id
                }
            }

            is WSMessage.SelectionChangedMessage -> {
                _selectedSessionId.value = message.selectedSessionId
            }

            is WSMessage.PairResultMessage -> {
                if (message.success) {
                    Log.d(TAG, "Pairing successful")
                    webSocketClient.markPaired()
                    requestSync()

                    // Save auth token from server response for reconnection
                    val token = message.message
                    if (!token.isNullOrEmpty()) {
                        preferencesRepository.saveAuthToken(token)
                        webSocketClient.authToken = token
                    }

                    // Stop mDNS discovery to release the multicast lock and save battery.
                    // Discovery is no longer needed once we are paired with a server.
                    bonjourDiscovery.stopDiscovery()

                    // Persist the server we just paired with
                    val server = webSocketClient.currentServer()
                    if (server != null) {
                        // Try to find the server name from discovered servers
                        val name = bonjourDiscovery.discoveredServers.value
                            .find { it.host == server.first && it.port == server.second }
                            ?.name ?: "ClaudeMulti"
                        saveLastServer(server.first, server.second, name)
                    }
                } else {
                    Log.w(TAG, "Pairing failed: ${message.message}")
                }
            }

            is WSMessage.ErrorMessage -> {
                Log.e(TAG, "Server error: ${message.message}")
            }

            // Outbound-only message types; should not be received from server
            is WSMessage.PairMessage,
            is WSMessage.CycleSelectionMessage,
            is WSMessage.SendTextMessage,
            is WSMessage.RequestSyncMessage -> {
                // No-op
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        bonjourDiscovery.destroy()
        pushToTalkManager.destroy()
        webSocketClient.disconnect()
    }
}

/**
 * Factory that creates [RemoteViewModel] with its dependencies.
 * Used in place of Hilt / other DI frameworks.
 */
class RemoteViewModelFactory(private val application: Application) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        val prefsRepo = PreferencesRepository(application)
        val discovery = BonjourDiscovery(application)
        val pttManager = PushToTalkManager()
        pttManager.initialize(application)
        @Suppress("UNCHECKED_CAST")
        return RemoteViewModel(WebSocketClient(), discovery, pttManager, prefsRepo) as T
    }
}

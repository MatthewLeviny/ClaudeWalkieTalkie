package com.claudemulti.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Represents a discovered ClaudeMulti server on the local network.
 */
data class ServerInfo(
    val host: String,
    val port: Int,
    val name: String
)

/**
 * Discovers ClaudeMulti servers on the local network via mDNS (Bonjour / NSD).
 *
 * Manages a [WifiManager.MulticastLock] to ensure multicast mDNS packets are
 * delivered to the app, and exposes the discovered servers as a reactive [StateFlow].
 *
 * The constructor accepts an application [Context] so that [startDiscovery] can be
 * called without passing a context each time.
 *
 * Usage:
 * ```
 * val discovery = BonjourDiscovery(applicationContext)
 * discovery.startDiscovery()
 * // observe discovery.discoveredServers
 * discovery.stopDiscovery()
 * ```
 */
class BonjourDiscovery(context: Context) {

    companion object {
        private const val TAG = "BonjourDiscovery"
        private const val SERVICE_TYPE = "_claudemulti._tcp."
        private const val MULTICAST_LOCK_TAG = "claudemulti_discovery"
        private const val RESTART_DELAY_MS = 2_000L
    }

    private val appContext: Context = context.applicationContext

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // --------------- NSD & Wi-Fi handles ---------------

    private var nsdManager: NsdManager? = null
    private var wifiManager: WifiManager? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    // --------------- public reactive state ---------------

    private val _discoveredServers = MutableStateFlow<List<ServerInfo>>(emptyList())
    /** Servers currently visible on the network. */
    val discoveredServers: StateFlow<List<ServerInfo>> = _discoveredServers.asStateFlow()

    private val _isDiscovering = MutableStateFlow(false)
    /** `true` while NSD discovery is actively running. */
    val isDiscovering: StateFlow<Boolean> = _isDiscovering.asStateFlow()

    // --------------- discovery listener (single instance for the lifetime of a discovery session) ---------------

    private var discoveryListener: NsdManager.DiscoveryListener? = null

    /**
     * When true, [stopDiscovery] was called intentionally and we should not auto-restart.
     */
    @Volatile
    private var stoppedIntentionally = false

    // --------------- public API ---------------

    /**
     * Begin discovering ClaudeMulti servers.
     *
     * Acquires a [WifiManager.MulticastLock] so the device receives mDNS multicast
     * packets, then registers an NSD discovery listener for [SERVICE_TYPE].
     *
     * Safe to call multiple times -- subsequent calls while already discovering are no-ops.
     */
    fun startDiscovery() {
        if (_isDiscovering.value) {
            Log.d(TAG, "Already discovering; ignoring duplicate startDiscovery call")
            return
        }

        stoppedIntentionally = false

        nsdManager = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
        wifiManager = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        // Acquire multicast lock so the Wi-Fi driver forwards mDNS packets
        multicastLock = wifiManager!!.createMulticastLock(MULTICAST_LOCK_TAG).apply {
            setReferenceCounted(true)
            acquire()
        }
        Log.d(TAG, "MulticastLock acquired")

        // Build a fresh listener for this discovery session
        val listener = createDiscoveryListener()
        discoveryListener = listener

        try {
            nsdManager!!.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (e: Exception) {
            Log.e(TAG, "discoverServices threw: ${e.message}")
            scheduleRestart()
        }
    }

    /**
     * Stop discovering servers and release the multicast lock.
     *
     * Clears the [discoveredServers] list.
     */
    fun stopDiscovery() {
        stoppedIntentionally = true

        discoveryListener?.let { listener ->
            try {
                nsdManager?.stopServiceDiscovery(listener)
            } catch (e: IllegalArgumentException) {
                // Listener was not registered or already stopped -- safe to ignore
                Log.w(TAG, "stopServiceDiscovery: ${e.message}")
            }
        }
        discoveryListener = null

        releaseMulticastLock()

        _isDiscovering.value = false
        _discoveredServers.value = emptyList()
    }

    /**
     * Cancel the internal coroutine scope. Call when the discovery will no
     * longer be used (e.g. ViewModel.onCleared).
     */
    fun destroy() {
        stopDiscovery()
        scope.cancel()
    }

    // --------------- auto-restart ---------------

    /**
     * Schedule an automatic restart of discovery after a brief delay.
     * Only restarts if [stoppedIntentionally] is false.
     */
    private fun scheduleRestart() {
        if (stoppedIntentionally) return
        scope.launch {
            Log.d(TAG, "Scheduling discovery restart in ${RESTART_DELAY_MS}ms")
            delay(RESTART_DELAY_MS)
            if (!stoppedIntentionally && !_isDiscovering.value) {
                Log.i(TAG, "Auto-restarting discovery")
                releaseMulticastLock()
                discoveryListener = null
                startDiscovery()
            }
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "MulticastLock released")
            }
        }
        multicastLock = null
    }

    // --------------- listener factories ---------------

    private fun createDiscoveryListener(): NsdManager.DiscoveryListener =
        object : NsdManager.DiscoveryListener {

            override fun onDiscoveryStarted(serviceType: String) {
                Log.i(TAG, "Discovery started for $serviceType")
                _isDiscovering.value = true
            }

            override fun onDiscoveryStopped(serviceType: String) {
                Log.i(TAG, "Discovery stopped for $serviceType")
                _isDiscovering.value = false
                // Auto-restart if discovery stopped unexpectedly
                if (!stoppedIntentionally) {
                    scheduleRestart()
                }
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                Log.d(TAG, "Service found: ${serviceInfo.serviceName}")
                resolveService(serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                Log.d(TAG, "Service lost: ${serviceInfo.serviceName}")
                _discoveredServers.value = _discoveredServers.value.filter {
                    it.name != serviceInfo.serviceName
                }
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e(TAG, "Start discovery failed: errorCode=$errorCode")
                _isDiscovering.value = false
                // Auto-restart on failure
                scheduleRestart()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e(TAG, "Stop discovery failed: errorCode=$errorCode")
            }
        }

    /**
     * Resolve a discovered service to obtain its host address and port.
     *
     * On API 34+ (Android 14) uses the newer [NsdManager.ServiceInfoCallback] which
     * supports concurrent resolutions. On older versions falls back to the deprecated
     * [NsdManager.ResolveListener] (which can only handle one resolution at a time --
     * failures from concurrent calls are logged and silently skipped).
     */
    private fun resolveService(serviceInfo: NsdServiceInfo) {
        val manager = nsdManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // API 34+ : ServiceInfoCallback supports concurrent resolution
            resolveServiceModern(manager, serviceInfo)
        } else {
            resolveServiceLegacy(manager, serviceInfo)
        }
    }

    /**
     * API 34+ resolution using [NsdManager.ServiceInfoCallback].
     */
    private fun resolveServiceModern(manager: NsdManager, serviceInfo: NsdServiceInfo) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                    Log.e(TAG, "ServiceInfoCallback registration failed: errorCode=$errorCode")
                }

                override fun onServiceUpdated(updatedInfo: NsdServiceInfo) {
                    addResolvedService(updatedInfo)
                    // Unregister after the first successful update -- we only need the address once
                    try {
                        manager.unregisterServiceInfoCallback(this)
                    } catch (_: Exception) { /* best-effort */ }
                }

                override fun onServiceLost() {
                    // Handled by DiscoveryListener.onServiceLost
                }

                override fun onServiceInfoCallbackUnregistered() {
                    // no-op
                }
            }
            manager.registerServiceInfoCallback(
                serviceInfo,
                { it.run() },   // direct executor
                callback
            )
        }
    }

    /**
     * Pre-API-34 resolution using the legacy [NsdManager.ResolveListener].
     *
     * NsdManager only allows one outstanding [resolveService] call at a time on older
     * APIs. If a second call collides, [onResolveFailed] fires with
     * `FAILURE_ALREADY_ACTIVE`; we simply log and drop the event.
     */
    @Suppress("DEPRECATION")
    private fun resolveServiceLegacy(manager: NsdManager, serviceInfo: NsdServiceInfo) {
        val listener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "Resolve failed for ${info.serviceName}: errorCode=$errorCode")
            }

            override fun onServiceResolved(info: NsdServiceInfo) {
                addResolvedService(info)
            }
        }
        try {
            manager.resolveService(serviceInfo, listener)
        } catch (e: Exception) {
            Log.w(TAG, "resolveService threw: ${e.message}")
        }
    }

    /**
     * Add a successfully resolved service to [_discoveredServers], de-duplicating
     * by host+port. If a server with the same host:port already exists, it is
     * replaced only if the name has changed, otherwise the duplicate is ignored.
     */
    private fun addResolvedService(serviceInfo: NsdServiceInfo) {
        val hostAddress = serviceInfo.host?.hostAddress
        if (hostAddress == null) {
            Log.w(TAG, "Resolved service ${serviceInfo.serviceName} has no host address")
            return
        }

        val server = ServerInfo(
            host = hostAddress,
            port = serviceInfo.port,
            name = serviceInfo.serviceName
        )

        // Thread-safe update: read-copy-write on the StateFlow value
        val current = _discoveredServers.value
        val existingIndex = current.indexOfFirst { it.host == server.host && it.port == server.port }
        if (existingIndex >= 0) {
            // Update name if it changed, otherwise ignore duplicate
            val existing = current[existingIndex]
            if (existing.name != server.name) {
                _discoveredServers.value = current.toMutableList().apply {
                    set(existingIndex, server)
                }
                Log.i(TAG, "Updated server name: $server")
            } else {
                Log.d(TAG, "Duplicate server ignored: $server")
            }
        } else {
            _discoveredServers.value = current + server
            Log.i(TAG, "Resolved server: $server")
        }
    }
}

package com.claudemulti.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.claudemulti.network.ConnectionState
import com.claudemulti.network.ServerInfo
import com.claudemulti.viewmodel.LastServer
import com.claudemulti.viewmodel.RemoteViewModel

@Composable
fun ConnectionScreen(
    viewModel: RemoteViewModel,
    onConnected: () -> Unit,
    modifier: Modifier = Modifier
) {
    val discoveredServers by viewModel.discoveredServers.collectAsStateWithLifecycle()
    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()
    val connectionError by viewModel.connectionError.collectAsStateWithLifecycle()
    val lastServer by viewModel.lastServer.collectAsStateWithLifecycle()

    var manualHost by remember { mutableStateOf("") }
    var manualPort by remember { mutableStateOf("8765") }
    var pairingCode by remember { mutableStateOf("") }
    var autoConnectAttempted by remember { mutableStateOf(false) }

    // When connectionState changes to Paired, call onConnected
    LaunchedEffect(connectionState) {
        if (connectionState == ConnectionState.Paired) {
            onConnected()
        }
    }

    // Auto-connect to last known server if it appears in discovered servers
    LaunchedEffect(discoveredServers, lastServer) {
        if (autoConnectAttempted) return@LaunchedEffect
        val saved = lastServer ?: return@LaunchedEffect
        if (connectionState != ConnectionState.Disconnected) return@LaunchedEffect

        val match = discoveredServers.find { it.host == saved.host && it.port == saved.port }
        if (match != null) {
            autoConnectAttempted = true
            viewModel.connect(match.host, match.port)
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Title
        Text(
            text = "ClaudeMulti Remote",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(4.dp))

        // Connection status indicator
        ConnectionStatusBar(connectionState)

        // Error display with retry
        if (connectionError != null && connectionState == ConnectionState.Disconnected) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                )
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Connection Failed",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                    Text(
                        text = connectionError ?: "Unknown error",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                    OutlinedButton(
                        onClick = {
                            autoConnectAttempted = false
                            // Retry last known server or let the user pick again
                            val saved = lastServer
                            if (saved != null) {
                                viewModel.connect(saved.host, saved.port)
                            }
                        },
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.onErrorContainer
                        )
                    ) {
                        Text("Retry")
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        // --- Pairing section (shown when Connected but not yet Paired) ---
        if (connectionState == ConnectionState.Connected) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "Enter Pairing Code",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                    Text(
                        text = "Enter the 6-digit code shown on your Mac app.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.Bottom
                    ) {
                        OutlinedTextField(
                            value = pairingCode,
                            onValueChange = { if (it.length <= 6) pairingCode = it },
                            label = { Text("Pairing Code") },
                            placeholder = { Text("000000") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        Button(
                            onClick = {
                                if (pairingCode.isNotBlank()) {
                                    viewModel.sendPairingCode(pairingCode.trim())
                                }
                            },
                            enabled = pairingCode.length == 6
                        ) {
                            Text("Pair")
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
        }

        // --- Server lists (shown when Disconnected or Connecting) ---
        if (connectionState == ConnectionState.Disconnected ||
            connectionState == ConnectionState.Connecting
        ) {
            // Previously connected server
            if (lastServer != null && connectionState == ConnectionState.Disconnected) {
                val saved = lastServer!!
                Text(
                    text = "Previously Connected",
                    style = MaterialTheme.typography.titleMedium
                )
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.connect(saved.host, saved.port) },
                    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer
                    )
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Star,
                            contentDescription = "Last connected",
                            tint = MaterialTheme.colorScheme.onSecondaryContainer,
                            modifier = Modifier.size(20.dp)
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = saved.name.ifEmpty { "ClaudeMulti Server" },
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSecondaryContainer
                            )
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                text = "${saved.host}:${saved.port}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f)
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            }

            // Discovered Servers
            Text(
                text = "Discovered Servers",
                style = MaterialTheme.typography.titleMedium
            )

            if (discoveredServers.isEmpty()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.padding(vertical = 8.dp)
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp
                    )
                    Column {
                        Text(
                            text = "Searching...",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Text(
                            text = "Make sure your Mac app is running",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(discoveredServers) { server ->
                        ServerCard(
                            server = server,
                            isConnecting = connectionState == ConnectionState.Connecting,
                            onClick = { viewModel.connect(server.host, server.port) }
                        )
                    }
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

            // --- Manual Connection section ---
            Text(
                text = "Manual Connection",
                style = MaterialTheme.typography.titleMedium
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Bottom
            ) {
                OutlinedTextField(
                    value = manualHost,
                    onValueChange = { manualHost = it },
                    label = { Text("IP Address") },
                    placeholder = { Text("192.168.1.100") },
                    singleLine = true,
                    modifier = Modifier.weight(2f)
                )

                OutlinedTextField(
                    value = manualPort,
                    onValueChange = { manualPort = it },
                    label = { Text("Port") },
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
            }

            Button(
                onClick = {
                    val port = manualPort.toIntOrNull() ?: 8765
                    if (manualHost.isNotBlank()) {
                        viewModel.connect(manualHost.trim(), port)
                    }
                },
                enabled = manualHost.isNotBlank() &&
                    connectionState == ConnectionState.Disconnected,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (connectionState == ConnectionState.Connecting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text(
                    if (connectionState == ConnectionState.Connecting) "Connecting..."
                    else "Connect"
                )
            }
        }

        // Push bottom spacer
        Spacer(modifier = Modifier.weight(1f))

        // Connection state indicator at bottom
        Text(
            text = when (connectionState) {
                ConnectionState.Disconnected -> "Not connected"
                ConnectionState.Connecting -> "Connecting..."
                ConnectionState.Connected -> "Connected -- enter pairing code above"
                ConnectionState.Paired -> "Paired successfully!"
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.align(Alignment.CenterHorizontally)
        )
    }
}

@Composable
private fun ConnectionStatusBar(state: ConnectionState) {
    val (text, color) = when (state) {
        ConnectionState.Disconnected -> "Disconnected" to MaterialTheme.colorScheme.error
        ConnectionState.Connecting -> "Connecting..." to MaterialTheme.colorScheme.tertiary
        ConnectionState.Connected -> "Connected" to MaterialTheme.colorScheme.primary
        ConnectionState.Paired -> "Paired" to MaterialTheme.colorScheme.primary
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (state == ConnectionState.Connecting) {
            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
        }
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            color = color
        )
    }
}

@Composable
private fun ServerCard(
    server: ServerInfo,
    isConnecting: Boolean,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !isConnecting, onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = server.name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "${server.host}:${server.port}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (isConnecting) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp
                )
            }
        }
    }
}

package com.claudemulti.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.claudemulti.network.ConnectionState
import com.claudemulti.speech.PTTState
import com.claudemulti.viewmodel.RemoteViewModel

@Composable
fun MainScreen(
    viewModel: RemoteViewModel,
    modifier: Modifier = Modifier
) {
    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()
    val sessions by viewModel.sessions.collectAsStateWithLifecycle()
    val selectedSessionId by viewModel.selectedSessionId.collectAsStateWithLifecycle()
    val screenBounds by viewModel.screenBounds.collectAsStateWithLifecycle()
    val pttState by viewModel.pttState.collectAsStateWithLifecycle()
    val partialTranscription by viewModel.partialTranscription.collectAsStateWithLifecycle()
    val volumeInterceptionEnabled by viewModel.volumeInterceptionEnabled.collectAsStateWithLifecycle()
    val isStale by viewModel.isStale.collectAsStateWithLifecycle()

    val snackbarHostState = remember { SnackbarHostState() }

    // Show snackbar when connection becomes stale
    LaunchedEffect(isStale) {
        if (isStale) {
            snackbarHostState.showSnackbar(
                message = "Connection lost. Reconnecting...",
                duration = SnackbarDuration.Indefinite
            )
        } else {
            snackbarHostState.currentSnackbarData?.dismiss()
        }
    }

    Scaffold(
        snackbarHost = {
            SnackbarHost(hostState = snackbarHostState) { data ->
                Snackbar(
                    snackbarData = data,
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                    contentColor = MaterialTheme.colorScheme.onErrorContainer
                )
            }
        },
        containerColor = Color.Transparent
    ) { paddingValues ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(8.dp)
        ) {
            // --- Top bar ---
            TopBar(
                connectionState = connectionState,
                isStale = isStale,
                volumeInterceptionEnabled = volumeInterceptionEnabled,
                onToggleVolumeInterception = {
                    viewModel.volumeInterceptionEnabled.value = it
                },
                onDisconnect = { viewModel.disconnect() }
            )

            Spacer(modifier = Modifier.height(8.dp))

            // --- Center: Window map with stale overlay ---
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) {
                WindowMapView(
                    sessions = sessions,
                    screenBounds = screenBounds,
                    selectedSessionId = selectedSessionId,
                    modifier = Modifier.fillMaxSize()
                )

                // Stale state overlay
                if (isStale) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Color.Black.copy(alpha = 0.5f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(32.dp),
                                color = Color.White,
                                strokeWidth = 3.dp
                            )
                            Text(
                                text = "Reconnecting...",
                                style = MaterialTheme.typography.titleMedium,
                                color = Color.White
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(8.dp))

            // --- Bottom card: selected session info + PTT indicator ---
            BottomInfoCard(
                sessions = sessions,
                selectedSessionId = selectedSessionId,
                pttState = pttState,
                partialTranscription = partialTranscription
            )

            // --- Controls hint ---
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Vol Down: Cycle | Vol Up: Push-to-Talk",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )
        }
    }
}

@Composable
private fun TopBar(
    connectionState: ConnectionState,
    isStale: Boolean,
    volumeInterceptionEnabled: Boolean,
    onToggleVolumeInterception: (Boolean) -> Unit,
    onDisconnect: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Left: connection status dot + text
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            val dotColor by animateColorAsState(
                targetValue = when {
                    isStale -> Color(0xFFFF9800) // Orange for stale
                    connectionState == ConnectionState.Paired -> Color(0xFF4CAF50)  // Green
                    connectionState == ConnectionState.Connected -> Color(0xFFFFC107) // Amber
                    connectionState == ConnectionState.Connecting -> Color(0xFFFF9800) // Orange
                    else -> Color(0xFFF44336) // Red
                },
                label = "connectionDot"
            )
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .clip(CircleShape)
                    .background(dotColor)
            )
            Text(
                text = when {
                    isStale -> "Reconnecting..."
                    connectionState == ConnectionState.Paired -> "Connected"
                    else -> connectionState.name
                },
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium
            )
        }

        // Center: volume interception toggle
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = "Vol",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Switch(
                checked = volumeInterceptionEnabled,
                onCheckedChange = onToggleVolumeInterception
            )
        }

        // Right: disconnect button
        Button(
            onClick = onDisconnect,
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error
            )
        ) {
            Text("Disconnect", style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun BottomInfoCard(
    sessions: List<com.claudemulti.protocol.TerminalSession>,
    selectedSessionId: String?,
    pttState: PTTState,
    partialTranscription: String
) {
    val selected = sessions.find { it.id == selectedSessionId }

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            // Selected session info
            if (selected != null) {
                Text(
                    text = "Selected: ${selected.title}",
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Bounds: (${selected.bounds.x.toInt()}, ${selected.bounds.y.toInt()}) " +
                        "${selected.bounds.width.toInt()}x${selected.bounds.height.toInt()}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text(
                    text = "No session selected",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            // PTT state indicator
            PTTIndicator(pttState = pttState)

            // Partial transcription (shown during Listening/Processing)
            if (pttState == PTTState.Listening || pttState == PTTState.Processing) {
                if (partialTranscription.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = partialTranscription,
                        style = MaterialTheme.typography.bodyMedium,
                        fontStyle = FontStyle.Italic,
                        color = MaterialTheme.colorScheme.primary,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

@Composable
private fun PTTIndicator(pttState: PTTState) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        when (pttState) {
            PTTState.Listening -> {
                // Pulsing red dot for active recording
                val infiniteTransition = rememberInfiniteTransition(label = "pttPulse")
                val scale by infiniteTransition.animateFloat(
                    initialValue = 0.8f,
                    targetValue = 1.4f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(durationMillis = 600),
                        repeatMode = RepeatMode.Reverse
                    ),
                    label = "pttPulseScale"
                )
                val alpha by infiniteTransition.animateFloat(
                    initialValue = 1f,
                    targetValue = 0.5f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(durationMillis = 600),
                        repeatMode = RepeatMode.Reverse
                    ),
                    label = "pttPulseAlpha"
                )
                Box(
                    modifier = Modifier
                        .size(12.dp)
                        .scale(scale)
                        .alpha(alpha)
                        .clip(CircleShape)
                        .background(Color(0xFFF44336))
                )
            }
            PTTState.Processing -> {
                // Spinner for processing
                CircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    strokeWidth = 2.dp,
                    color = Color(0xFFFFC107)
                )
            }
            else -> {
                // Static dot for idle/error
                val dotColor by animateColorAsState(
                    targetValue = when (pttState) {
                        PTTState.Idle -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                        PTTState.Error -> Color(0xFFFF5722)
                        else -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                    },
                    label = "pttDot"
                )
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(dotColor)
                )
            }
        }

        Text(
            text = when (pttState) {
                PTTState.Idle -> "Ready"
                PTTState.Listening -> "Listening..."
                PTTState.Processing -> "Processing..."
                PTTState.Error -> "Error"
            },
            style = MaterialTheme.typography.labelMedium,
            color = when (pttState) {
                PTTState.Listening -> Color(0xFFF44336)
                PTTState.Processing -> Color(0xFFFFC107)
                PTTState.Error -> Color(0xFFFF5722)
                else -> MaterialTheme.colorScheme.onSurfaceVariant
            }
        )
    }
}

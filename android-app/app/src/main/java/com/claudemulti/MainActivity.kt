package com.claudemulti

import android.Manifest
import android.os.Bundle
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.claudemulti.network.ConnectionState
import com.claudemulti.ui.ConnectionScreen
import com.claudemulti.ui.MainScreen
import com.claudemulti.viewmodel.RemoteViewModel
import com.claudemulti.viewmodel.RemoteViewModelFactory

class MainActivity : ComponentActivity() {

    private val viewModel: RemoteViewModel by viewModels { RemoteViewModelFactory(application) }

    private var isVolumeUpHeld = false
    private var permissionGranted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    // Request RECORD_AUDIO permission on launch
                    var permissionState by remember { mutableStateOf(false) }
                    val permissionLauncher = rememberLauncherForActivityResult(
                        contract = ActivityResultContracts.RequestPermission()
                    ) { granted ->
                        permissionState = granted
                        permissionGranted = granted
                    }

                    LaunchedEffect(Unit) {
                        permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                    }

                    // Handle reconnection on resume / pause via Compose lifecycle effect
                    LifecycleResumeEffect(viewModel) {
                        viewModel.onResume()
                        onPauseOrDispose {
                            viewModel.onPause()
                        }
                    }

                    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()

                    when (connectionState) {
                        ConnectionState.Disconnected,
                        ConnectionState.Connecting,
                        ConnectionState.Connected -> {
                            ConnectionScreen(
                                viewModel = viewModel,
                                onConnected = {
                                    // Navigation handled reactively via connectionState
                                }
                            )
                        }

                        ConnectionState.Paired -> {
                            MainScreen(viewModel = viewModel)
                        }
                    }
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!viewModel.volumeInterceptionEnabled.value) {
            return super.dispatchKeyEvent(event)
        }

        return when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    viewModel.cycleSelection()
                    // Haptic feedback for cycle selection
                    window.decorView.performHapticFeedback(
                        HapticFeedbackConstants.VIRTUAL_KEY
                    )
                }
                true // Consume both ACTION_DOWN and ACTION_UP
            }

            KeyEvent.KEYCODE_VOLUME_UP -> {
                when (event.action) {
                    KeyEvent.ACTION_DOWN -> {
                        if (!isVolumeUpHeld) {
                            isVolumeUpHeld = true
                            viewModel.startVoice(hasPermission = permissionGranted)
                            // Haptic feedback for PTT start
                            window.decorView.performHapticFeedback(
                                HapticFeedbackConstants.LONG_PRESS
                            )
                        }
                        true
                    }
                    KeyEvent.ACTION_UP -> {
                        isVolumeUpHeld = false
                        viewModel.stopVoice()
                        // Light haptic feedback for PTT stop
                        window.decorView.performHapticFeedback(
                            HapticFeedbackConstants.VIRTUAL_KEY
                        )
                        true
                    }
                    else -> true
                }
            }

            else -> super.dispatchKeyEvent(event)
        }
    }
}

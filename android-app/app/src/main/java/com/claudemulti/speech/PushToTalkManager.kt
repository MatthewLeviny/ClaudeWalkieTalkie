package com.claudemulti.speech

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import com.claudemulti.BuildConfig
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

enum class PTTState {
    Idle,
    Listening,
    Processing,
    Error
}

/**
 * Manages push-to-talk speech recognition lifecycle.
 *
 * State machine: Idle -> Listening -> Processing -> Idle
 *                Idle -> Listening -> Error -> Idle (on fatal errors)
 *
 * Usage:
 *   val ptt = PushToTalkManager()
 *   ptt.initialize(context)
 *   ptt.startListening()   // on VOLUME_UP press
 *   ptt.stopListening()    // on VOLUME_UP release
 *   // Observe ptt.finalResult for recognized text
 *   ptt.destroy()
 */
class PushToTalkManager {

    companion object {
        private const val TAG = "PushToTalkManager"
    }

    private var speechRecognizer: SpeechRecognizer? = null
    private var appContext: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val _state = MutableStateFlow(PTTState.Idle)
    val state: StateFlow<PTTState> = _state.asStateFlow()

    private val _partialResult = MutableStateFlow("")
    val partialResult: StateFlow<String> = _partialResult.asStateFlow()

    private val _finalResult = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val finalResult: SharedFlow<String> = _finalResult.asSharedFlow()

    private val recognitionListener = object : RecognitionListener {

        override fun onReadyForSpeech(params: Bundle?) {
            Log.d(TAG, "onReadyForSpeech")
            _state.value = PTTState.Listening
        }

        override fun onBeginningOfSpeech() {
            Log.d(TAG, "onBeginningOfSpeech")
            // Already in Listening state
        }

        override fun onRmsChanged(rmsdB: Float) {
            // Could expose audio level for UI visualization
        }

        override fun onBufferReceived(buffer: ByteArray?) {
            // Not typically used
        }

        override fun onEndOfSpeech() {
            Log.d(TAG, "onEndOfSpeech")
            _state.value = PTTState.Processing
        }

        override fun onError(error: Int) {
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH -> {
                    // Non-fatal: user didn't speak or was too quiet
                    Log.d(TAG, "onError: ERROR_NO_MATCH (no speech detected)")
                    _partialResult.value = ""
                    _state.value = PTTState.Idle
                }
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                    // Non-fatal: user released without speaking long enough
                    Log.d(TAG, "onError: ERROR_SPEECH_TIMEOUT")
                    _partialResult.value = ""
                    _state.value = PTTState.Idle
                }
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> {
                    // Recognizer is busy processing previous request; just log and ignore
                    Log.w(TAG, "onError: ERROR_RECOGNIZER_BUSY — ignoring")
                }
                else -> {
                    Log.e(TAG, "onError: error code $error")
                    _partialResult.value = ""
                    _state.value = PTTState.Error
                }
            }
        }

        override fun onResults(results: Bundle?) {
            val matches = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)

            val bestResult = matches?.firstOrNull().orEmpty()
            val capped = bestResult.take(1000)
            if (BuildConfig.DEBUG) Log.d(TAG, "onResults: \"$capped\"")

            if (capped.isNotEmpty()) {
                _finalResult.tryEmit(capped)
            }

            _partialResult.value = ""
            _state.value = PTTState.Idle
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val partial = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                .orEmpty()
            _partialResult.value = partial
        }

        override fun onEvent(eventType: Int, params: Bundle?) {
            // Reserved for future use
        }
    }

    /**
     * Initialize the speech recognizer. Must be called before [startListening].
     * Creates the [SpeechRecognizer] on the main thread as required by Android.
     */
    fun initialize(context: Context) {
        appContext = context.applicationContext
        mainHandler.post {
            if (speechRecognizer == null) {
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(appContext).also {
                    it.setRecognitionListener(recognitionListener)
                }
                Log.d(TAG, "SpeechRecognizer initialized")
            }
        }
    }

    /**
     * Begin listening for speech. Only transitions from [PTTState.Idle].
     * Rapid start/stop is guarded: calls from non-Idle states are ignored.
     */
    fun startListening() {
        if (_state.value != PTTState.Idle) {
            Log.d(TAG, "startListening ignored — current state: ${_state.value}")
            return
        }

        val ctx = appContext ?: run {
            Log.e(TAG, "startListening called before initialize()")
            return
        }

        _partialResult.value = ""

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        mainHandler.post {
            // Re-create recognizer if it was destroyed or null
            if (speechRecognizer == null) {
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(ctx).also {
                    it.setRecognitionListener(recognitionListener)
                }
            }
            speechRecognizer?.startListening(intent)
            Log.d(TAG, "startListening dispatched")
        }
    }

    /**
     * Stop listening. The recognizer will process any buffered audio
     * and deliver results via [RecognitionListener.onResults].
     */
    fun stopListening() {
        if (_state.value == PTTState.Idle) return
        mainHandler.post {
            speechRecognizer?.stopListening()
            Log.d(TAG, "stopListening dispatched")
        }
    }

    /**
     * Release all resources. Call when the manager is no longer needed.
     */
    fun destroy() {
        mainHandler.post {
            speechRecognizer?.destroy()
            speechRecognizer = null
            Log.d(TAG, "SpeechRecognizer destroyed")
        }
        _state.value = PTTState.Idle
        _partialResult.value = ""
        appContext = null
    }
}

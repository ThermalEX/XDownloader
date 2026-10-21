package com.xdl.app

import android.app.Activity
import android.media.AudioManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlin.math.roundToInt

/** Runs on the activity thread. Never changes the system brightness setting. */
class PlaybackWindowControls(private val activity: Activity) {
    private val audio get() = activity.getSystemService(AudioManager::class.java)
    private var originalBrightness: Float? = null
    private var hadKeepScreenOn = false
    private var fullscreen = false

    fun handle(method: String, arguments: Any?): Any? {
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        return when (method) {
            "beginPlaybackControls" -> {
                if (originalBrightness == null) {
                    originalBrightness = activity.window.attributes.screenBrightness
                    hadKeepScreenOn = activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                read()
            }
            "readPlaybackControls" -> read()
            "setPlaybackBrightness" -> {
                check(originalBrightness != null) { "No active playback window" }
                val level = (args["value"] as Number).toFloat().coerceIn(0.02f, 1f)
                activity.window.attributes = activity.window.attributes.apply { screenBrightness = level }
                level.toDouble()
            }
            "setPlaybackVolume" -> {
                check(originalBrightness != null) { "No active playback window" }
                val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val level = (args["value"] as Number).toDouble().coerceIn(0.0, 1.0)
                if (!audio.isVolumeFixed && max > 0) audio.setStreamVolume(AudioManager.STREAM_MUSIC, (level * max).roundToInt(), 0)
                volume()
            }
            "setPlaybackFullscreen" -> { setFullscreen(args["value"] == true); null }
            "endPlaybackControls" -> { end(); null }
            else -> error("Unknown playback method")
        }
    }

    private fun volume(): Double {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        return if (max > 0) audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max else 0.0
    }

    private fun read(): Map<String, Any> {
        val window = activity.window.attributes.screenBrightness
        val system = Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0
        return mapOf("brightness" to (if (window >= 0) window.toDouble() else system).coerceIn(0.02, 1.0),
            "windowBrightness" to window.toDouble(), "systemBrightness" to system,
            "keepScreenOn" to (activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0),
            "volume" to volume(), "volumeFixed" to audio.isVolumeFixed, "fullscreen" to fullscreen)
    }

    private fun setFullscreen(enabled: Boolean) {
        fullscreen = enabled
        val controller = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (enabled) controller.hide(WindowInsetsCompat.Type.systemBars()) else controller.show(WindowInsetsCompat.Type.systemBars())
    }

    fun end() {
        originalBrightness?.let { original ->
            activity.window.attributes = activity.window.attributes.apply { screenBrightness = original }
            if (!hadKeepScreenOn) activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        originalBrightness = null
        setFullscreen(false)
    }

    companion object {
        val methods = setOf("beginPlaybackControls", "readPlaybackControls", "setPlaybackBrightness", "setPlaybackVolume", "setPlaybackFullscreen", "endPlaybackControls")
    }
}

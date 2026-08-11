package com.sunpad.android

import android.content.Context
import android.media.AudioManager

/**
 * Native audio-property helper consumed by the core's OpenSL ES backend
 * (see the SunPad OpenSLESStream patch). The class and static method names
 * are a contract with the native side — do not rename without updating
 * `Source/Core/AudioCommon/OpenSLESStream.cpp` in the SunPad Dolphin patch.
 */
object AudioUtils {
    @JvmStatic
    fun getSampleRate(): Int =
        readIntProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE) ?: 48000

    @JvmStatic
    fun getFramesPerBuffer(): Int =
        readIntProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER) ?: 240

    private fun readIntProperty(property: String): Int? {
        val manager = SunPadApp.appContext.getSystemService(Context.AUDIO_SERVICE)
                as? AudioManager ?: return null
        return manager.getProperty(property)?.toIntOrNull()
    }
}

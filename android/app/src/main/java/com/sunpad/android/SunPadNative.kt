package com.sunpad.android

import android.view.Surface

/**
 * Native bridge to libsunpad.so (JNI shim + ModernGekko runtime host +
 * the merged Dolphin-derived core). All native methods are declared here;
 * the C++ side lives in android/app/src/main/cpp/.
 */
object SunPadNative {

    val available: Boolean
    val loadError: String?

    init {
        var ok = false
        var error: String? = null
        try {
            System.loadLibrary("sunpad")
            ok = true
        } catch (t: Throwable) {
            error = t.message ?: t.javaClass.simpleName
            android.util.Log.e("SunPad", "libsunpad.so failed to load", t)
        }
        available = ok
        loadError = error
    }

    /** Progress/completion callback for on-device disc extraction (invoked
     *  on a native worker thread; marshal to the UI thread on the caller). */
    interface ExtractProgressListener {
        fun onProgress(status: String, fraction: Double)
        fun onFinished(success: Boolean, message: String?)
    }

    /**
     * Boots the game on a native background thread. Blocks until the runtime
     * has been created (or has failed) so the app can show the error instead
     * of appearing to crash.
     * @return null on success, otherwise a human-readable error message.
     */
    fun start(
        gameRoot: String,
        discImage: String?,
        modulePath: String,
        userDirectory: String,
    ): String? {
        if (!available) return loadError ?: "Native library is not loaded."
        return try {
            nativeStart(gameRoot, discImage, modulePath, userDirectory)
        } catch (t: Throwable) {
            android.util.Log.e("SunPad", "nativeStart threw", t)
            t.message ?: "nativeStart failed"
        }
    }

    fun stop() = ifAvailable { nativeStop() }

    fun pause() = ifAvailable { nativePause() }

    fun resume() = ifAvailable { nativeResume() }

    fun setSurface(surface: Surface?) = ifAvailable { nativeSetSurface(surface) }

    fun publishInput(state: GameInputState) = ifAvailable { nativePublishInput(state) }

    fun setRenderScale(scale: Int) = ifAvailable { nativeSetRenderScale(scale) }

    fun setAspectRatioMode(mode: Int) = ifAvailable { nativeSetAspectRatioMode(mode) }

    fun setModernCStick(enabled: Boolean) = ifAvailable { nativeSetModernCStick(enabled) }

    fun setCrashLogPath(path: String) = ifAvailable { nativeSetCrashLogPath(path) }

    fun setPreferredBackend(backend: String) = ifAvailable { nativeSetPreferredBackend(backend) }

    fun setExperimental60Fps(enabled: Boolean) =
        ifAvailable { nativeSetExperimental60Fps(enabled) }

    fun setDualCore(enabled: Boolean) = ifAvailable { nativeSetDualCore(enabled) }

    fun currentFPS(): Double = if (available) nativeCurrentFPS() else 0.0

    fun currentSpeed(): Double = if (available) nativeCurrentSpeed() else 0.0

    fun efbResolution(): String = if (available) nativeEfbResolution() else ""

    fun isRunning(): Boolean = available && nativeIsRunning()

    fun extractImage(
        imagePath: String,
        destination: String,
        listener: ExtractProgressListener,
    ) {
        if (!available) {
            listener.onFinished(false, loadError ?: "Native library is not loaded.")
            return
        }
        nativeExtractImage(imagePath, destination, listener)
    }

    private inline fun ifAvailable(block: () -> Unit) {
        if (available) {
            try {
                block()
            } catch (t: Throwable) {
                android.util.Log.e("SunPad", "native call failed", t)
            }
        }
    }

    /**
     * Boots the game on a native background thread and returns immediately.
     * @return null on success, otherwise a human-readable error message.
     */
    private external fun nativeStart(
        gameRoot: String,
        discImage: String?,
        modulePath: String,
        userDirectory: String,
    ): String?

    private external fun nativeStop()

    private external fun nativePause()

    private external fun nativeResume()

    private external fun nativeSetSurface(surface: Surface?)

    private external fun nativePublishInput(state: GameInputState)

    private external fun nativeSetRenderScale(scale: Int)

    private external fun nativeSetAspectRatioMode(mode: Int)

    private external fun nativeSetModernCStick(enabled: Boolean)

    private external fun nativeSetCrashLogPath(path: String)

    private external fun nativeSetPreferredBackend(backend: String)

    private external fun nativeSetExperimental60Fps(enabled: Boolean)

    private external fun nativeSetDualCore(enabled: Boolean)

    private external fun nativeCurrentFPS(): Double

    private external fun nativeCurrentSpeed(): Double

    private external fun nativeEfbResolution(): String

    private external fun nativeIsRunning(): Boolean

    private external fun nativeExtractImage(
        imagePath: String,
        destination: String,
        listener: ExtractProgressListener,
    )
}

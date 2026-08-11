package com.sunpad.android

import android.view.Surface

/**
 * Native bridge to libsunpad.so (JNI shim + ModernGekko runtime host +
 * the merged Dolphin-derived core). All native methods are declared here;
 * the C++ side lives in android/app/src/main/cpp/.
 */
object SunPadNative {

    init {
        System.loadLibrary("sunpad")
    }

    /** Progress/completion callback for on-device disc extraction (invoked
     *  on a native worker thread; marshal to the UI thread on the caller). */
    interface ExtractProgressListener {
        fun onProgress(status: String, fraction: Double)
        fun onFinished(success: Boolean, message: String?)
    }

    /**
     * Boots the game on a native background thread and returns immediately.
     * @return null on success, otherwise a human-readable error message.
     */
    external fun nativeStart(
        gameRoot: String,
        discImage: String?,
        modulePath: String,
        userDirectory: String,
    ): String?

    /** Requests a graceful runtime shutdown and joins the game thread. */
    external fun nativeStop()

    /** Pauses emulation (app backgrounded / surface destroyed). */
    external fun nativePause()

    /** Resumes emulation (app foregrounded / surface recreated). */
    external fun nativeResume()

    /** Hands the current Surface to the Vulkan backend via ANativeWindow.
     *  Pass null when the surface is destroyed. */
    external fun nativeSetSurface(surface: Surface?)

    /** Publishes one normalized input snapshot to the Pipes device. */
    external fun nativePublishInput(state: GameInputState)

    /** 1x–4x internal (EFB) render scale. */
    external fun nativeSetRenderScale(scale: Int)

    /** 0 = original 4:3, 1 = widescreen, 2 = fill screen. */
    external fun nativeSetAspectRatioMode(mode: Int)

    external fun nativeSetModernCStick(enabled: Boolean)

    external fun nativeCurrentFPS(): Double

    external fun nativeCurrentSpeed(): Double

    external fun nativeEfbResolution(): String

    external fun nativeIsRunning(): Boolean

    /**
     * Extracts a validated raw ISO/GCM with the core's DiscIO into
     * [destination] (game files under files/, system data at the root).
     * Blocks until extraction completes; call from a background thread.
     * [listener] receives progress and the final result.
     */
    external fun nativeExtractImage(
        imagePath: String,
        destination: String,
        listener: ExtractProgressListener,
    )
}

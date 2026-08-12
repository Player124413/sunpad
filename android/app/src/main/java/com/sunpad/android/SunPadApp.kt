package com.sunpad.android

import android.app.Application
import android.content.Context
import java.io.File

/** Process-level context holder so the native audio bridge can reach
 *  Android framework services without an Activity reference. */
class SunPadApp : Application() {
    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext
        installCrashHandler()
    }

    /**
     * Catches uncaught exceptions: writes the stack trace to
     * sunpad_crash.log so the next launch can show it. Application-context
     * dialogs are not shown here (they crash with BadTokenException and
     * then the process still dies).
     */
    private fun installCrashHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val stack = android.util.Log.getStackTraceString(throwable)
                android.util.Log.e("SunPadCrash", "Uncaught on ${thread.name}", throwable)
                try {
                    File(filesDir, "sunpad_crash.log").writeText(
                        "Thread: ${thread.name}\n$stack")
                } catch (_: Exception) {
                }
            } finally {
                defaultHandler?.uncaughtException(thread, throwable)
            }
        }
    }

    companion object {
        lateinit var appContext: Context
            private set
    }
}

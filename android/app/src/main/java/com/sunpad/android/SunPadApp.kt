package com.sunpad.android

import android.app.Application
import android.app.AlertDialog
import android.content.Context
import android.os.Handler
import android.os.Looper
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
     * sunpad_crash.log in app storage and shows the message in a dialog so
     * the user can report it instead of just seeing the app close.
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
                Handler(Looper.getMainLooper()).post {
                    try {
                        AlertDialog.Builder(appContext)
                            .setTitle("SunPad error")
                            .setMessage(stack.take(1500))
                            .setPositiveButton("OK", null)
                            .show()
                    } catch (_: Exception) {
                    }
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

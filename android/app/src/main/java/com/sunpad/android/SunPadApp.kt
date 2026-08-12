package com.sunpad.android

import android.app.Application
import android.content.Context

/** Process-level context holder so the native audio bridge can reach
 *  Android framework services without an Activity reference. */
class SunPadApp : Application() {
    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext
        DiagnosticLog.ensurePublicFolder(this)
        installCrashHandler()
    }

    /**
     * Catches uncaught exceptions: writes the stack trace to
     * sunpad_crash.log (private + Android/data/com.sunpad.android/files)
     * so the next launch can show it and the user can copy it.
     */
    private fun installCrashHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val stack = android.util.Log.getStackTraceString(throwable)
                android.util.Log.e("SunPadCrash", "Uncaught on ${thread.name}", throwable)
                DiagnosticLog.append(this, "Uncaught on ${thread.name}\n$stack")
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

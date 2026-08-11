package com.sunpad.android

import android.app.Application
import android.content.Context

/** Process-level context holder so the native audio bridge can reach
 *  Android framework services without an Activity reference. */
class SunPadApp : Application() {
    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext
    }

    companion object {
        lateinit var appContext: Context
            private set
    }
}

package com.sunpad.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Diagnostic log that is written both to private storage and to the
 * user-visible `Android/data/com.sunpad.android/files/` folder (created on
 * first use — that folder does not exist until the app touches external
 * files). Copy-to-clipboard is the share path from the three-dot menu.
 */
object DiagnosticLog {

    private const val PRIVATE_NAME = "sunpad_crash.log"
    private const val PUBLIC_NAME = "sunpad.log"

    fun privateFile(context: Context): File = File(context.filesDir, PRIVATE_NAME)

    fun publicDir(context: Context): File? = try {
        context.getExternalFilesDir(null)
    } catch (_: Exception) {
        null
    }

    fun publicFile(context: Context): File? =
        publicDir(context)?.let { File(it, PUBLIC_NAME) }

    /** Creates Android/data/com.sunpad.android/files so a file manager can see it. */
    fun ensurePublicFolder(context: Context) {
        val dir = publicDir(context) ?: return
        dir.mkdirs()
        val readme = File(dir, "README.txt")
        if (!readme.isFile) {
            try {
                readme.writeText(
                    "SunPad diagnostic folder\n" +
                        "Package: com.sunpad.android\n" +
                        "sunpad.log — copy this (or use ••• → Copy diagnostic log).\n" +
                        "Game data stays in private app storage, not here.\n")
            } catch (_: Exception) {
            }
        }
    }

    fun append(context: Context, text: String) {
        val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
        val line = "[$stamp] $text\n"
        try {
            privateFile(context).appendText(line)
        } catch (_: Exception) {
        }
        try {
            ensurePublicFolder(context)
            publicFile(context)?.appendText(line)
        } catch (_: Exception) {
        }
        android.util.Log.e("SunPad", text)
    }

    fun read(context: Context): String {
        val private = try {
            val f = privateFile(context)
            if (f.isFile) f.readText() else ""
        } catch (_: Exception) { "" }
        val public = try {
            val f = publicFile(context)
            if (f.isFile) f.readText() else ""
        } catch (_: Exception) { "" }
        return when {
            private.isNotBlank() -> private
            public.isNotBlank() -> public
            else -> "(no log yet)"
        }
    }

    fun copyToClipboard(context: Context): String {
        val text = read(context)
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboard?.setPrimaryClip(ClipData.newPlainText("SunPad log", text))
        return text
    }
}

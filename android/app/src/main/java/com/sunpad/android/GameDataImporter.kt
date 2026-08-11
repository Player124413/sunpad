package com.sunpad.android

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile

/**
 * User-owned game-data import, mirroring the iOS flow: staged private copy ->
 * exact validation (size, GameCube magic, GMSE01, disc 0 revision 0) ->
 * on-device extraction with the core's DiscIO -> atomic activation.
 * Nothing is ever bundled; the user picks their own raw ISO/GCM.
 */
class GameDataImporter(private val context: Context) {

    val gameDir: File get() = File(context.filesDir, "game")
    val stagingDir: File get() = File(gameDir, "staging")
    val activeImage: File get() = File(gameDir, "GMSE01.iso")
    val activeRoot: File get() = File(gameDir, "GMSE01")
    val moduleDir: File get() = File(context.filesDir, "module")
    val moduleFile: File get() = File(moduleDir, "gGMSE01_recomp.so")
    val userDirectory: File get() = File(context.filesDir, "user")

    val gameRoot: File get() = activeRoot
    val discImagePath: String get() = activeImage.absolutePath
    val modulePath: String get() = moduleFile.absolutePath
    val userDirectoryPath: String get() = userDirectory.absolutePath

    fun hasActiveGame(): Boolean =
        activeImage.isFile && File(activeRoot, "files").isDirectory

    fun hasModule(): Boolean = moduleFile.isFile

    /** Returns a validation error string, or null when the image is valid. */
    fun validateImageFile(file: File): String? {
        if (file.length() != EXPECTED_SIZE)
            return "The image size does not match the supported GMSE01 USA revision 0 disc."
        val header = ByteArray(0x100)
        RandomAccessFile(file, "r").use { raf ->
            val read = raf.read(header)
            if (read < header.size)
                return "The file is too small to be a GameCube image."
        }
        val magic = ((header[0x1C].toInt() and 0xFF) shl 24) or
            ((header[0x1D].toInt() and 0xFF) shl 16) or
            ((header[0x1E].toInt() and 0xFF) shl 8) or
            (header[0x1F].toInt() and 0xFF)
        if (magic != DISC_MAGIC)
            return "The file is not a GameCube disc image (bad magic)."
        val gameId = String(header, 0, 6, Charsets.US_ASCII)
        if (gameId != GAME_ID)
            return "Unsupported game ID '$gameId'; SunPad currently supports GMSE01 (Super Mario Sunshine USA)."
        if (header[6].toInt() != 0 || header[7].toInt() != 0)
            return "SunPad currently supports disc 0, revision 0 only."
        return null
    }

    /**
     * Copies [uri] into the staging area and validates it.
     * @return error string or null on success.
     */
    fun copyAndValidate(uri: Uri, progress: (Float) -> Unit): String? {
        stagingDir.mkdirs()
        val staging = File(stagingDir, "GMSE01.iso")
        val size = querySize(uri)
        val input = context.contentResolver.openInputStream(uri)
            ?: return "The selected file could not be opened."
        input.use { source ->
            FileOutputStream(staging).use { out ->
                val buffer = ByteArray(1 shl 16)
                var total = 0L
                while (true) {
                    val n = source.read(buffer)
                    if (n < 0) break
                    out.write(buffer, 0, n)
                    total += n
                    if (size > 0)
                        progress((total.toFloat() / size.toFloat()).coerceIn(0f, 1f))
                }
            }
        }
        return validateImageFile(staging)
    }

    /**
     * Extracts the staged image into a staged tree, verifies the result, then
     * atomically activates image + tree (replacing any previous data).
     */
    fun extractAndActivate(progress: (String, Double) -> Unit): String? {
        val stagedImage = File(stagingDir, "GMSE01.iso")
        if (!stagedImage.isFile)
            return "No staged image to extract."
        val stagedRoot = File(stagingDir, "GMSE01")
        stagedRoot.deleteRecursively()

        var error: String? = null
        SunPadNative.nativeExtractImage(
            stagedImage.absolutePath, stagedRoot.absolutePath,
            object : SunPadNative.ExtractProgressListener {
                override fun onProgress(status: String, fraction: Double) {
                    progress(status, fraction)
                }

                override fun onFinished(success: Boolean, message: String?) {
                    if (!success) error = message ?: "Extraction failed."
                }
            })

        if (error != null) return error
        if (!File(stagedRoot, "files").isDirectory)
            return "Extraction produced no files tree; import rejected."

        // Atomic activation: replace previous data only after full success.
        activeImage.delete()
        activeRoot.deleteRecursively()
        gameDir.mkdirs()
        if (!stagedImage.renameTo(activeImage))
            return "Could not activate the imported image."
        if (!stagedRoot.renameTo(activeRoot)) {
            activeImage.delete()
            return "Could not activate the extracted game data."
        }
        return null
    }

    /** Copies a user-picked recompiled module into app storage. */
    fun importModule(uri: Uri): String? {
        moduleDir.mkdirs()
        val input = context.contentResolver.openInputStream(uri)
            ?: return "The selected module could not be opened."
        input.use { source ->
            FileOutputStream(moduleFile).use { out ->
                source.copyTo(out)
            }
        }
        return if (moduleFile.isFile) null else "Module copy failed."
    }

    /** Removes imported game data (module stays; saves stay separate). */
    fun removeGameData() {
        activeImage.delete()
        activeRoot.deleteRecursively()
    }

    private fun querySize(uri: Uri): Long {
        val cursor = context.contentResolver.query(
            uri, arrayOf(OpenableColumns.SIZE), null, null, null) ?: return -1L
        return cursor.use {
            if (it.moveToFirst()) it.getLong(0) else -1L
        }
    }

    companion object {
        const val EXPECTED_SIZE = 1459978240L
        const val DISC_MAGIC = 0xC2339F3D
        const val GAME_ID = "GMSE01"
    }
}

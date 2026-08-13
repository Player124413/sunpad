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
    val sysDirectory: File get() = File(userDirectory, "Sys")

    val gameRoot: File get() = activeRoot
    val discImagePath: String get() = activeImage.absolutePath
    val modulePath: String get() = moduleFile.absolutePath
    val userDirectoryPath: String get() = userDirectory.absolutePath

    fun hasActiveGame(): Boolean =
        activeImage.isFile && File(activeRoot, "files").isDirectory

    fun hasModule(): Boolean = moduleFile.isFile && validateModuleFile(moduleFile) == null

    /**
     * Ensures the game module is available in private storage. If the module
     * was bundled into the APK assets (CI builds with SUNPAD_BUNDLE_MODULE=1),
     * it is extracted to the module directory on first launch; otherwise a
     * user-provided module copied earlier is used.
     */
    fun ensureModule(): Boolean {
        if (hasModule()) return true
        if (moduleFile.isFile) {
            // A previous import wrote a file that is not a valid Android .so
            // (ISO, iOS dylib, desktop module). Drop it so the setup dialog
            // asks again instead of crashing inside dlopen.
            android.util.Log.w("SunPad", "rejecting invalid module: ${validateModuleFile(moduleFile)}")
            moduleFile.delete()
        }
        return try {
            context.assets.open("modules/gGMSE01_recomp.so").use { input ->
                moduleDir.mkdirs()
                FileOutputStream(moduleFile).use { out -> input.copyTo(out) }
            }
            hasModule()
        } catch (_: java.io.IOException) {
            false
        }
    }

    /** @return a human-readable error, or null when [file] is an arm64 .so. */
    fun validateModuleFile(file: File): String? {
        if (!file.isFile || file.length() < 64L)
            return "The module file is missing or too small."
        val header = ByteArray(20)
        RandomAccessFile(file, "r").use { raf ->
            if (raf.read(header) < header.size)
                return "The module file could not be read."
        }
        return ModuleValidator.validateHeader(header)
    }

    /**
     * Copies bundled Dolphin Sys data (GameSettings, GC fonts, etc.) from
     * APK assets into the user directory. Dolphin Android ASSERT-aborts if
     * File::SetSysDirectory is never called / the folder is missing.
     */
    fun ensureDolphinSys(): File {
        userDirectory.mkdirs()
        sysDirectory.mkdirs()
        val marker = File(sysDirectory, "GameSettings")
        if (marker.isDirectory) {
            DiagnosticLog.append(context, "dolphin Sys already present at ${sysDirectory.absolutePath}")
            return sysDirectory
        }
        try {
            copyAssetTree("dolphin-sys", sysDirectory)
        } catch (t: Throwable) {
            android.util.Log.w("SunPad", "dolphin-sys assets not copied", t)
            DiagnosticLog.append(context, "dolphin-sys assets not copied: ${t.message}")
        }
        val ready = File(sysDirectory, "GameSettings").isDirectory
        DiagnosticLog.append(
            context,
            if (ready) "dolphin Sys extracted to ${sysDirectory.absolutePath}"
            else "dolphin Sys folder is empty (rebuild the APK so CI can bundle Data/Sys)",
        )
        return sysDirectory
    }

    private fun copyAssetTree(assetPath: String, dest: File) {
        dest.mkdirs()
        val names = context.assets.list(assetPath) ?: return
        for (name in names) {
            val childAsset = "$assetPath/$name"
            val childDest = File(dest, name)
            val nested = context.assets.list(childAsset)
            if (nested != null && nested.isNotEmpty()) {
                copyAssetTree(childAsset, childDest)
            } else {
                context.assets.open(childAsset).use { input ->
                    FileOutputStream(childDest).use { input.copyTo(it) }
                }
            }
        }
    }

    /** Bytes that should be free before a full ISO copy + extract. */
    fun requiredFreeBytes(): Long = EXPECTED_SIZE * 2 + 256L * 1024L * 1024L

    fun hasEnoughSpace(): Boolean = context.filesDir.usableSpace >= requiredFreeBytes()

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
        if (!hasEnoughSpace())
            return "Not enough free space. SunPad needs about 3.2 GB to copy and extract the disc."
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
        try {
            SunPadNative.extractImage(
                stagedImage.absolutePath, stagedRoot.absolutePath,
                object : SunPadNative.ExtractProgressListener {
                    override fun onProgress(status: String, fraction: Double) {
                        progress(status, fraction)
                    }

                    override fun onFinished(success: Boolean, message: String?) {
                        if (!success) error = message ?: "Extraction failed."
                    }
                })
        } catch (t: Throwable) {
            android.util.Log.e("SunPad", "extract threw", t)
            return t.message ?: "Extraction crashed."
        }

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
        if (!moduleFile.isFile) return "Module copy failed."
        val error = validateModuleFile(moduleFile)
        if (error != null) {
            moduleFile.delete()
            return error
        }
        return null
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
        // 0xC2339F3D does not fit in a positive Int; store it as the Int
        // bit pattern (the negative two's-complement value).
        val DISC_MAGIC: Int = 0xC2339F3D.toInt()
        const val GAME_ID = "GMSE01"
    }
}

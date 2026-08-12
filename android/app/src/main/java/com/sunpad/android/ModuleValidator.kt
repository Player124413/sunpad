package com.sunpad.android

/**
 * Cheap ELF header check so a user-picked ISO, iOS dylib, or desktop
 * module is rejected *before* dlopen can abort the process.
 */
object ModuleValidator {

    private const val ELF_MAGIC_0 = 0x7f
    private const val ELF_MAGIC_1 = 'E'.code
    private const val ELF_MAGIC_2 = 'L'.code
    private const val ELF_MAGIC_3 = 'F'.code
    private const val ELFCLASS64 = 2
    private const val ELFDATA2LSB = 1
    private const val ET_DYN = 3
    private const val EM_AARCH64 = 183

    /** @return null when [header] looks like an Android arm64 .so. */
    fun validateHeader(header: ByteArray): String? {
        if (header.size < 20)
            return "The module file is too small to be a native library."
        if ((header[0].toInt() and 0xFF) != ELF_MAGIC_0 ||
            (header[1].toInt() and 0xFF) != ELF_MAGIC_1 ||
            (header[2].toInt() and 0xFF) != ELF_MAGIC_2 ||
            (header[3].toInt() and 0xFF) != ELF_MAGIC_3) {
            return "That file is not an Android game module. Pick gGMSE01_recomp.so " +
                "(not the ISO, and not an iOS or Mac file)."
        }
        if ((header[4].toInt() and 0xFF) != ELFCLASS64)
            return "The module is not 64-bit. SunPad only runs on 64-bit ARM Android."
        if ((header[5].toInt() and 0xFF) != ELFDATA2LSB)
            return "The module has an unexpected byte order."
        val type = u16(header, 16)
        val machine = u16(header, 18)
        if (machine != EM_AARCH64)
            return "The module is not arm64 (machine=$machine). " +
                "An emulator or x86 build will not run on this device."
        if (type != ET_DYN)
            return "The module is not a shared library (type=$type)."
        return null
    }

    private fun u16(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xFF) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 8)
}

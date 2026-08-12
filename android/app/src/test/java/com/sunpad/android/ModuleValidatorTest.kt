package com.sunpad.android

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ModuleValidatorTest {

    @Test
    fun rejectsTooSmall() {
        assertNotNull(ModuleValidator.validateHeader(ByteArray(8)))
    }

    @Test
    fun rejectsIsoMagic() {
        val header = ByteArray(20)
        // GameCube disc magic lives at 0x1C; the first bytes are the game id.
        header[0] = 'G'.code.toByte()
        header[1] = 'M'.code.toByte()
        header[2] = 'S'.code.toByte()
        header[3] = 'E'.code.toByte()
        val error = ModuleValidator.validateHeader(header)
        assertNotNull(error)
        assertTrue(error!!.contains("not an Android game module"))
    }

    @Test
    fun acceptsArm64SharedObject() {
        val header = ByteArray(20)
        header[0] = 0x7f
        header[1] = 'E'.code.toByte()
        header[2] = 'L'.code.toByte()
        header[3] = 'F'.code.toByte()
        header[4] = 2 // ELFCLASS64
        header[5] = 1 // ELFDATA2LSB
        header[16] = 3 // ET_DYN
        header[17] = 0
        header[18] = 183.toByte() // EM_AARCH64
        header[19] = 0
        assertNull(ModuleValidator.validateHeader(header))
    }

    @Test
    fun rejectsX86() {
        val header = ByteArray(20)
        header[0] = 0x7f
        header[1] = 'E'.code.toByte()
        header[2] = 'L'.code.toByte()
        header[3] = 'F'.code.toByte()
        header[4] = 2
        header[5] = 1
        header[16] = 3
        header[18] = 62 // EM_X86_64
        val error = ModuleValidator.validateHeader(header)
        assertNotNull(error)
        assertTrue(error!!.contains("not arm64"))
    }
}

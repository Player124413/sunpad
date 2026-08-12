package com.sunpad.android.input

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Persistence format for the touch-layout editor. A drag that is not written
 * back into the in-memory map (and then encoded as a full set) used to snap
 * buttons back to their defaults after Done.
 */
class TouchLayoutCodecTest {

    @Test
    fun originsRoundTrip() {
        val saved = mapOf(
            "A" to (0.86f to 0.60f),
            "move" to (0.20f to 0.55f),
            "Start" to (0.50f to 0.80f),
        )
        val encoded = TouchLayoutCodec.encodeOrigins(saved)
        val decoded = TouchLayoutCodec.decodeOrigins(encoded)
        assertEquals(saved.keys, decoded.keys)
        for ((id, xy) in saved) {
            assertEquals(xy.first, decoded.getValue(id).first, 0.0001f)
            assertEquals(xy.second, decoded.getValue(id).second, 0.0001f)
        }
    }

    @Test
    fun rewritingWholeSetKeepsEarlierButtons() {
        // The old incremental getStringSet/putStringSet path could drop a
        // previously saved button when a second one was moved.
        val first = TouchLayoutCodec.encodeOrigins(mapOf("A" to (0.1f to 0.2f)))
        val merged = TouchLayoutCodec.decodeOrigins(first)
        merged["B"] = 0.3f to 0.4f
        val second = TouchLayoutCodec.decodeOrigins(TouchLayoutCodec.encodeOrigins(merged))
        assertEquals(setOf("A", "B"), second.keys)
        assertEquals(0.1f, second.getValue("A").first, 0.0001f)
        assertEquals(0.3f, second.getValue("B").first, 0.0001f)
    }

    @Test
    fun scalesClampAndIgnoreJunk() {
        val decoded = TouchLayoutCodec.decodeScales(
            setOf("A=1.2", "B=not-a-float", "C=9.0", "broken"),
            0.60f,
            1.75f,
        )
        assertEquals(1.2f, decoded.getValue("A"), 0.0001f)
        assertEquals(1.75f, decoded.getValue("C"), 0.0001f)
        assertTrue(!decoded.containsKey("B"))
        assertTrue(!decoded.containsKey("broken"))
    }

    @Test
    fun emptyAndNullDecodeToEmpty() {
        assertTrue(TouchLayoutCodec.decodeOrigins(null).isEmpty())
        assertTrue(TouchLayoutCodec.decodeOrigins(emptySet()).isEmpty())
        assertTrue(TouchLayoutCodec.decodeScales(null, 0.6f, 1.75f).isEmpty())
    }
}

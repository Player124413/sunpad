package com.sunpad.android.input

/**
 * Encode / decode the persisted touch-layout maps. Kept as a pure helper so
 * the StringSet format can be regression-tested without an Android View.
 *
 * Each origin is stored as `id=x,y` with x/y normalized to 0..1.
 * Each size scale is stored as `id=value`.
 */
internal object TouchLayoutCodec {

    fun decodeOrigins(raw: Set<String>?): MutableMap<String, Pair<Float, Float>> {
        val out = HashMap<String, Pair<Float, Float>>()
        raw?.forEach { entry ->
            val parts = entry.split("=")
            if (parts.size != 2) return@forEach
            val xy = parts[1].split(",")
            if (xy.size != 2) return@forEach
            val x = xy[0].toFloatOrNull() ?: return@forEach
            val y = xy[1].toFloatOrNull() ?: return@forEach
            out[parts[0]] = x.coerceIn(0f, 1f) to y.coerceIn(0f, 1f)
        }
        return out
    }

    fun encodeOrigins(map: Map<String, Pair<Float, Float>>): Set<String> =
        map.map { (id, xy) -> "$id=${xy.first},${xy.second}" }.toSet()

    fun decodeScales(raw: Set<String>?, min: Float, max: Float): MutableMap<String, Float> {
        val out = HashMap<String, Float>()
        raw?.forEach { entry ->
            val parts = entry.split("=")
            if (parts.size != 2) return@forEach
            parts[1].toFloatOrNull()?.let { out[parts[0]] = it.coerceIn(min, max) }
        }
        return out
    }

    fun encodeScales(map: Map<String, Float>): Set<String> =
        map.map { (id, value) -> "$id=$value" }.toSet()
}

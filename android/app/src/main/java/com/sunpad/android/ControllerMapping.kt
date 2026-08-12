package com.sunpad.android

import android.content.Context

/**
 * Android port of apple/shared/SunPadControllerMapping.mm: the deliberately
 * narrow A/B/X/Y/Z physical-button remapping layer for gamepads.
 *
 * Only five physical buttons participate: A, B, X, Y, and the right
 * shoulder. Sticks, D-pad, Start, left shoulder, and analog triggers keep
 * their established direct mappings (BellPad semantics: the right shoulder
 * is GameCube Z by default, analog triggers carry L/R pressure).
 */

/** Physical controller buttons participating in remapping. */
enum class PhysicalButton(val bit: Int, val label: String) {
    A(1 shl 0, "A"),
    B(1 shl 1, "B"),
    X(1 shl 2, "X"),
    Y(1 shl 3, "Y"),
    RIGHT_SHOULDER(1 shl 4, "Right Shoulder");

    companion object {
        val ALL: List<PhysicalButton> = entries.toList()

        // Not const: bitwise-or of enum properties is not a compile-time
        // constant expression.
        val ALL_BITS: Int =
            A.bit or B.bit or X.bit or Y.bit or RIGHT_SHOULDER.bit

        fun fromBit(bit: Int): PhysicalButton? = entries.firstOrNull { it.bit == bit }
    }
}

/** GameCube A/B/X/Y/Z -> physical button assignment (one-to-one swap). */
data class ButtonMapping(
    val gameA: PhysicalButton = PhysicalButton.A,
    val gameB: PhysicalButton = PhysicalButton.B,
    val gameX: PhysicalButton = PhysicalButton.X,
    val gameY: PhysicalButton = PhysicalButton.Y,
    val gameZ: PhysicalButton = PhysicalButton.RIGHT_SHOULDER,
) {
    fun physicalFor(gameBit: Int): PhysicalButton? = when (gameBit) {
        SunPadButtons.A -> gameA
        SunPadButtons.B -> gameB
        SunPadButtons.X -> gameX
        SunPadButtons.Y -> gameY
        SunPadButtons.Z -> gameZ
        else -> null
    }

    fun isValid(): Boolean {
        var seen = 0
        for (button in listOf(gameA, gameB, gameX, gameY, gameZ)) {
            val bit = button.bit
            if (bit == 0 ||
                (bit and (bit - 1)) != 0 ||
                (bit and PhysicalButton.ALL_BITS.inv()) != 0 ||
                (seen and bit) != 0
            ) {
                return false
            }
            seen = seen or bit
        }
        return seen == PhysicalButton.ALL_BITS
    }

    fun withPhysical(gameBit: Int, value: PhysicalButton): ButtonMapping =
        when (gameBit) {
            SunPadButtons.A -> copy(gameA = value)
            SunPadButtons.B -> copy(gameB = value)
            SunPadButtons.X -> copy(gameX = value)
            SunPadButtons.Y -> copy(gameY = value)
            SunPadButtons.Z -> copy(gameZ = value)
            else -> this
        }
}

object ControllerMapping {

    private const val PREFS_FILE = "sunpad"
    private const val PREFS_KEY = "SunPadControllerButtonMappingV1"

    fun default(): ButtonMapping = ButtonMapping()

    /** Maps pressed physical-button bits to GameCube button bits. */
    fun applyMapping(mapping: ButtonMapping, pressedPhysicalBits: Int): Int {
        val m = if (mapping.isValid()) mapping else default()
        var gameButtons = 0
        if ((pressedPhysicalBits and m.gameA.bit) != 0) gameButtons = gameButtons or SunPadButtons.A
        if ((pressedPhysicalBits and m.gameB.bit) != 0) gameButtons = gameButtons or SunPadButtons.B
        if ((pressedPhysicalBits and m.gameX.bit) != 0) gameButtons = gameButtons or SunPadButtons.X
        if ((pressedPhysicalBits and m.gameY.bit) != 0) gameButtons = gameButtons or SunPadButtons.Y
        if ((pressedPhysicalBits and m.gameZ.bit) != 0) gameButtons = gameButtons or SunPadButtons.Z
        return gameButtons
    }

    /**
     * Assigns [physical] to the game button [gameBit]. If the physical button
     * is already assigned elsewhere, the two assignments swap (1:1 mapping).
     */
    fun assign(mapping: ButtonMapping, physical: PhysicalButton, gameBit: Int): ButtonMapping {
        val m = if (mapping.isValid()) mapping else default()
        val previous = m.physicalFor(gameBit) ?: return m
        if (previous == physical) return m
        var out = m
        for (candidate in GAME_BUTTONS) {
            if (candidate != gameBit && m.physicalFor(candidate) == physical) {
                out = out.withPhysical(candidate, previous)
                break
            }
        }
        return out.withPhysical(gameBit, physical)
    }

    fun load(context: Context): ButtonMapping {
        val raw = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getString(PREFS_KEY, null) ?: return default()
        val values = HashMap<String, Int>()
        for (part in raw.split(",")) {
            val kv = part.split("=")
            if (kv.size == 2) {
                kv[1].toIntOrNull()?.let { values[kv[0]] = it }
            }
        }
        val mapping = ButtonMapping(
            gameA = PhysicalButton.fromBit(values["A"] ?: 0) ?: return default(),
            gameB = PhysicalButton.fromBit(values["B"] ?: 0) ?: return default(),
            gameX = PhysicalButton.fromBit(values["X"] ?: 0) ?: return default(),
            gameY = PhysicalButton.fromBit(values["Y"] ?: 0) ?: return default(),
            gameZ = PhysicalButton.fromBit(values["Z"] ?: 0) ?: return default(),
        )
        return if (mapping.isValid()) mapping else default()
    }

    fun save(context: Context, mapping: ButtonMapping) {
        val m = if (mapping.isValid()) mapping else default()
        val text = listOf(
            "A=${m.gameA.bit}",
            "B=${m.gameB.bit}",
            "X=${m.gameX.bit}",
            "Y=${m.gameY.bit}",
            "Z=${m.gameZ.bit}",
        ).joinToString(",")
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit().putString(PREFS_KEY, text).apply()
    }

    fun reset(context: Context) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit().remove(PREFS_KEY).apply()
    }

    private val GAME_BUTTONS = listOf(
        SunPadButtons.A, SunPadButtons.B, SunPadButtons.X,
        SunPadButtons.Y, SunPadButtons.Z,
    )
}

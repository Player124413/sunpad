package com.sunpad.android

import android.view.Surface

/**
 * Normalized GameCube controller snapshot mirroring the Apple shared
 * SunPadInputState: sticks are [-127, 127], triggers [0, 255]
 * (FLUDD pressure), buttons a bitmask with BellPad-compatible bits.
 */
data class GameInputState(
    var stickX: Int = 0,
    var stickY: Int = 0,
    var cStickX: Int = 0,
    var cStickY: Int = 0,
    var triggerL: Int = 0,
    var triggerR: Int = 0,
    var buttons: Int = 0,
) {
    fun reset() {
        stickX = 0; stickY = 0; cStickX = 0; cStickY = 0
        triggerL = 0; triggerR = 0; buttons = 0
    }

    fun copyFrom(other: GameInputState) {
        stickX = other.stickX; stickY = other.stickY
        cStickX = other.cStickX; cStickY = other.cStickY
        triggerL = other.triggerL; triggerR = other.triggerR
        buttons = other.buttons
    }
}

/** Button bit layout must match apple/shared/SunPadInputState.h exactly. */
object SunPadButtons {
    const val DPAD_LEFT = 1 shl 0
    const val DPAD_RIGHT = 1 shl 1
    const val DPAD_DOWN = 1 shl 2
    const val DPAD_UP = 1 shl 3
    const val Z = 1 shl 4
    const val R = 1 shl 5
    const val L = 1 shl 6
    const val A = 1 shl 8
    const val B = 1 shl 9
    const val X = 1 shl 10
    const val Y = 1 shl 11
    const val START = 1 shl 12
}

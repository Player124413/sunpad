package com.sunpad.android.input

import android.content.Context
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import com.sunpad.android.ControllerMapping
import com.sunpad.android.GameInputState
import com.sunpad.android.PhysicalButton
import com.sunpad.android.SunPadButtons
import kotlin.math.abs
import kotlin.math.max

/**
 * Merges a connected Android gamepad (KeyEvent + joystick MotionEvents) into
 * the normalized GameCube state, mirroring the Apple shared input mixer:
 * ORed buttons, strongest-wins sticks, max analog triggers.
 *
 * BellPad semantics: the physical face buttons and the right shoulder are
 * remappable (A/B/X/Y/Z layer, default A/B/X/Y + right-shoulder = Z); the
 * left shoulder is GameCube L; the analog trigger axes carry L/R pressure
 * (FLUDD); the D-pad and Start map directly.
 */
class GamepadReader(private val context: Context) {

    private var mapping = ControllerMapping.load(context)
    private var physicalButtons = 0
    private var gameExtraButtons = 0
    private var stickX = 0f; private var stickY = 0f
    private var cStickX = 0f; private var cStickY = 0f
    private var triggerL = 0f; private var triggerR = 0f

    /** Re-reads the persisted mapping (called after remapping UI changes). */
    fun reloadMapping() {
        mapping = ControllerMapping.load(context)
    }

    /** Attach to the root view to receive key + joystick events. */
    fun attach(view: View) {
        view.setOnKeyListener { _, keyCode, event -> onKey(keyCode, event) }
        view.setOnGenericMotionListener { _, event -> onMotion(event) }
        view.isFocusableInTouchMode = true
        view.requestFocus()
    }

    fun detach(view: View) {
        view.setOnKeyListener(null)
        view.setOnGenericMotionListener(null)
    }

    fun reset() {
        physicalButtons = 0
        gameExtraButtons = 0
        stickX = 0f; stickY = 0f
        cStickX = 0f; cStickY = 0f
        triggerL = 0f; triggerR = 0f
    }

    private fun onKey(keyCode: Int, event: KeyEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_GAMEPAD) == 0) return false
        if (event.action != KeyEvent.ACTION_DOWN && event.action != KeyEvent.ACTION_UP)
            return false
        val down = event.action == KeyEvent.ACTION_DOWN
        if (down && event.repeatCount > 0) return true

        val physicalBit = physicalBitFor(keyCode)
        if (physicalBit != null) {
            physicalButtons = if (down) physicalButtons or physicalBit
                              else physicalButtons and physicalBit.inv()
            return true
        }
        val extraBit = extraGameBitFor(keyCode)
        if (extraBit != null) {
            gameExtraButtons = if (down) gameExtraButtons or extraBit
                               else gameExtraButtons and extraBit.inv()
            return true
        }
        return false
    }

    private fun physicalBitFor(keyCode: Int): Int? = when (keyCode) {
        KeyEvent.KEYCODE_BUTTON_A -> PhysicalButton.A.bit
        KeyEvent.KEYCODE_BUTTON_B -> PhysicalButton.B.bit
        KeyEvent.KEYCODE_BUTTON_X -> PhysicalButton.X.bit
        KeyEvent.KEYCODE_BUTTON_Y -> PhysicalButton.Y.bit
        KeyEvent.KEYCODE_BUTTON_R1 -> PhysicalButton.RIGHT_SHOULDER.bit
        else -> null
    }

    /** Non-remappable direct game bits: D-pad, L shoulder, Start. */
    private fun extraGameBitFor(keyCode: Int): Int? = when (keyCode) {
        KeyEvent.KEYCODE_DPAD_UP -> SunPadButtons.DPAD_UP
        KeyEvent.KEYCODE_DPAD_DOWN -> SunPadButtons.DPAD_DOWN
        KeyEvent.KEYCODE_DPAD_LEFT -> SunPadButtons.DPAD_LEFT
        KeyEvent.KEYCODE_DPAD_RIGHT -> SunPadButtons.DPAD_RIGHT
        KeyEvent.KEYCODE_BUTTON_L1 -> SunPadButtons.L
        KeyEvent.KEYCODE_BUTTON_START -> SunPadButtons.START
        else -> null
    }

    private fun onMotion(event: MotionEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_JOYSTICK) == 0) return false
        stickX = event.getAxisValue(MotionEvent.AXIS_X)
        stickY = event.getAxisValue(MotionEvent.AXIS_Y)
        cStickX = event.getAxisValue(MotionEvent.AXIS_RX)
        cStickY = event.getAxisValue(MotionEvent.AXIS_RY)
        triggerL = max(event.getAxisValue(MotionEvent.AXIS_LTRIGGER),
                       event.getAxisValue(MotionEvent.AXIS_BRAKE))
        triggerR = max(event.getAxisValue(MotionEvent.AXIS_RTRIGGER),
                       event.getAxisValue(MotionEvent.AXIS_GAS))
        return true
    }

    /** Merges the controller state into [into] (strongest-wins per axis). */
    fun merge(into: GameInputState) {
        into.buttons = into.buttons or
            ControllerMapping.applyMapping(mapping, physicalButtons) or
            gameExtraButtons
        if (abs(stickX * 127f) > abs(into.stickX))
            into.stickX = (stickX * 127f).toInt().coerceIn(-127, 127)
        if (abs(stickY * 127f) > abs(into.stickY))
            into.stickY = (stickY * 127f).toInt().coerceIn(-127, 127)
        if (abs(cStickX * 127f) > abs(into.cStickX))
            into.cStickX = (cStickX * 127f).toInt().coerceIn(-127, 127)
        if (abs(cStickY * 127f) > abs(into.cStickY))
            into.cStickY = (cStickY * 127f).toInt().coerceIn(-127, 127)
        into.triggerL = max(into.triggerL, (triggerL * 255f).toInt().coerceIn(0, 255))
        into.triggerR = max(into.triggerR, (triggerR * 255f).toInt().coerceIn(0, 255))
    }
}

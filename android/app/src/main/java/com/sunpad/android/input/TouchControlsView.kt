package com.sunpad.android.input

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.MotionEvent
import android.view.View
import com.sunpad.android.GameInputState
import com.sunpad.android.SunPadButtons
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * BellPad-style landscape touch overlay: move stick, camera (C) stick,
 * grouped D-pad, A/B/X/Y, Z, L, analog R, START, and the three-dot menu.
 * The layout is anchored to the surface; the activity can adjust opacity
 * and size from the menu.
 */
class TouchControlsView(context: Context) : View(context) {

    interface Listener {
        fun onMenuTap()
    }

    var listener: Listener? = null

    var opacity: Float = 0.55f
        set(value) {
            field = value.coerceIn(0.25f, 0.9f)
            invalidate()
        }
    var scale: Float = 1.0f
        set(value) {
            field = value.coerceIn(0.6f, 1.4f)
            requestLayout()
            invalidate()
        }

    private val state = GameInputState()
    private val stateLock = Any()

    private enum class Control { MOVE, C, DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT,
        A, B, X, Y, Z, L, R, START, MENU }

    private data class Zone(
        val control: Control,
        var cx: Float = 0f, var cy: Float = 0f, var radius: Float = 0f,
    )

    private val zones = Control.entries.associateWith { Zone(it) }
    private val pointers = HashMap<Int, Control>()
    private val stickOrigins = HashMap<Control, Pair<Float, Float>>()

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.argb(110, 255, 255, 255)
    }
    private val activePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.argb(150, 255, 214, 90)
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2f
        color = Color.argb(160, 255, 255, 255)
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(200, 30, 30, 30)
        textAlign = Paint.Align.CENTER
        typeface = android.graphics.Typeface.DEFAULT_BOLD
    }

    private var layoutDirty = true

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        layoutDirty = true
    }

    private fun layoutZones() {
        if (!layoutDirty) return
        layoutDirty = false
        val w = width.toFloat()
        val h = height.toFloat()
        val s = scale
        val rStick = 0.105f * w * s
        val rButton = 0.034f * w * s
        val rSmall = 0.028f * w * s

        zones.getValue(Control.MOVE).apply {
            cx = 0.155f * w; cy = 0.60f * h; radius = rStick
        }
        zones.getValue(Control.C).apply {
            cx = 0.585f * w; cy = 0.30f * h; radius = rStick * 0.85f
        }
        val dHalf = 0.065f * w * s
        zones.getValue(Control.DPAD_UP).apply { cx = 0.155f * w; cy = 0.84f * h - dHalf; radius = dHalf }
        zones.getValue(Control.DPAD_DOWN).apply { cx = 0.155f * w; cy = 0.84f * h + dHalf; radius = dHalf }
        zones.getValue(Control.DPAD_LEFT).apply { cx = 0.155f * w - dHalf; cy = 0.84f * h; radius = dHalf }
        zones.getValue(Control.DPAD_RIGHT).apply { cx = 0.155f * w + dHalf; cy = 0.84f * h; radius = dHalf }

        zones.getValue(Control.A).apply { cx = 0.865f * w; cy = 0.60f * h; radius = rButton }
        zones.getValue(Control.B).apply { cx = 0.795f * w; cy = 0.70f * h; radius = rButton }
        zones.getValue(Control.X).apply { cx = 0.865f * w; cy = 0.50f * h; radius = rButton }
        zones.getValue(Control.Y).apply { cx = 0.935f * w; cy = 0.60f * h; radius = rButton }
        zones.getValue(Control.Z).apply { cx = 0.70f * w; cy = 0.33f * h; radius = rSmall * 1.3f }
        zones.getValue(Control.L).apply { cx = 0.10f * w; cy = 0.09f * h; radius = rSmall * 1.6f }
        zones.getValue(Control.R).apply { cx = 0.90f * w; cy = 0.09f * h; radius = rSmall * 1.6f }
        zones.getValue(Control.START).apply { cx = 0.50f * w; cy = 0.90f * h; radius = rSmall * 1.5f }
        zones.getValue(Control.MENU).apply { cx = 0.955f * w; cy = 0.055f * h; radius = rSmall * 1.5f }
    }

    private fun controlAt(x: Float, y: Float): Control? {
        layoutZones()
        return zones.entries.firstOrNull { (c, z) ->
            c != Control.MENU && hypot(x - z.cx, y - z.cy) <= z.radius + 12f
        }?.key
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        layoutZones()
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val idx = if (event.actionMasked == MotionEvent.ACTION_DOWN) 0 else event.actionIndex
                val id = event.getPointerId(idx)
                val x = event.getX(idx); val y = event.getY(idx)
                val menu = zones.getValue(Control.MENU)
                if (hypot(x - menu.cx, y - menu.cy) <= menu.radius + 12f) {
                    listener?.onMenuTap()
                    return true
                }
                val control = controlAt(x, y) ?: return true
                pointers[id] = control
                if (control == Control.MOVE || control == Control.C)
                    stickOrigins[control] = x to y
                updateControl(control)
                invalidate()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until event.pointerCount) {
                    val id = event.getPointerId(i)
                    lastX[id] = event.getX(i)
                    lastY[id] = event.getY(i)
                    val control = pointers[id] ?: continue
                    updateControl(control)
                }
                invalidate()
                return true
            }
            MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val idx = if (event.actionMasked == MotionEvent.ACTION_POINTER_UP) event.actionIndex else 0
                val id = event.getPointerId(idx)
                lastX.remove(id)
                lastY.remove(id)
                val control = pointers.remove(id) ?: return true
                stickOrigins.remove(control)
                releaseControl(control)
                invalidate()
                return true
            }
        }
        return true
    }

    private fun updateControl(control: Control) {
        synchronized(stateLock) {
            when (control) {
                Control.MOVE, Control.C -> {
                    val origin = stickOrigins[control] ?: return
                    val zone = zones.getValue(control)
                    // Recompute from the most recent pointer position: the
                    // stick's resting origin is where the pointer landed.
                    val id = pointers.entries.firstOrNull { it.value == control }?.key ?: return
                    val x = lastX[id] ?: return
                    val y = lastY[id] ?: return
                    val dx = x - origin.first
                    val dy = y - origin.second
                    val radius = zone.radius
                    val dist = hypot(dx, dy)
                    val deadZone = radius * 0.10f
                    val nx = if (dist <= deadZone) 0f else (dx / dist).coerceIn(-1f, 1f) * min(1f, (dist - deadZone) / (radius - deadZone))
                    val ny = if (dist <= deadZone) 0f else (dy / dist).coerceIn(-1f, 1f) * min(1f, (dist - deadZone) / (radius - deadZone))
                    val vx = (nx * 127f).roundToInt().coerceIn(-127, 127)
                    val vy = (-ny * 127f).roundToInt().coerceIn(-127, 127)
                    if (control == Control.MOVE) {
                        state.stickX = vx; state.stickY = vy
                    } else {
                        state.cStickX = vx; state.cStickY = vy
                    }
                }
                else -> {
                    val bit = bitFor(control) ?: return
                    state.buttons = state.buttons or bit
                    if (control == Control.L) state.triggerL = 255
                    if (control == Control.R) state.triggerR = 255
                }
            }
        }
    }

    private fun releaseControl(control: Control) {
        synchronized(stateLock) {
            when (control) {
                Control.MOVE -> { state.stickX = 0; state.stickY = 0 }
                Control.C -> { state.cStickX = 0; state.cStickY = 0 }
                else -> {
                    val bit = bitFor(control) ?: return
                    state.buttons = state.buttons and bit.inv()
                    if (control == Control.L) state.triggerL = 0
                    if (control == Control.R) state.triggerR = 0
                }
            }
        }
    }

    private fun bitFor(control: Control): Int? = when (control) {
        Control.DPAD_UP -> SunPadButtons.DPAD_UP
        Control.DPAD_DOWN -> SunPadButtons.DPAD_DOWN
        Control.DPAD_LEFT -> SunPadButtons.DPAD_LEFT
        Control.DPAD_RIGHT -> SunPadButtons.DPAD_RIGHT
        Control.A -> SunPadButtons.A
        Control.B -> SunPadButtons.B
        Control.X -> SunPadButtons.X
        Control.Y -> SunPadButtons.Y
        Control.Z -> SunPadButtons.Z
        Control.L -> SunPadButtons.L
        Control.R -> SunPadButtons.R
        Control.START -> SunPadButtons.START
        else -> null
    }

    private val lastX = HashMap<Int, Float>()
    private val lastY = HashMap<Int, Float>()

    /** Copies the current touch state into [into] under the state lock. */
    fun snapshot(into: GameInputState) {
        synchronized(stateLock) {
            into.stickX = state.stickX
            into.stickY = state.stickY
            into.cStickX = state.cStickX
            into.cStickY = state.cStickY
            into.triggerL = state.triggerL
            into.triggerR = state.triggerR
            into.buttons = state.buttons
        }
    }

    /** Releases every active pointer (surface lost / activity paused). */
    fun releaseAll() {
        synchronized(stateLock) {
            pointers.clear()
            stickOrigins.clear()
            lastX.clear(); lastY.clear()
            state.reset()
        }
        invalidate()
    }

    private fun zoneOf(control: Control) = zones.getValue(control)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        layoutZones()
        val alpha = (opacity * 255).toInt().coerceIn(0, 255)
        fillPaint.alpha = alpha
        strokePaint.alpha = (alpha * 0.9f).toInt()
        labelPaint.textSize = zoneOf(Control.A).radius * 1.25f

        for ((control, zone) in zones) {
            val active = pointers.containsValue(control)
            val paint = if (active) activePaint else fillPaint
            when (control) {
                Control.MOVE -> {
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, paint)
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, strokePaint)
                    val dx = state.stickX / 127f * zone.radius
                    val dy = -state.stickY / 127f * zone.radius
                    canvas.drawCircle(zone.cx + dx, zone.cy + dy, zone.radius * 0.45f, strokePaint)
                }
                Control.C -> {
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, paint)
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, strokePaint)
                    val dx = state.cStickX / 127f * zone.radius
                    val dy = -state.cStickY / 127f * zone.radius
                    canvas.drawCircle(zone.cx + dx, zone.cy + dy, zone.radius * 0.45f, strokePaint)
                }
                Control.MENU -> {
                    // Three-dot menu handle.
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, paint)
                    val dot = zone.radius * 0.28f
                    for (i in -1..1) {
                        canvas.drawCircle(zone.cx + i * zone.radius * 0.5f, zone.cy, dot, labelPaint)
                    }
                }
                else -> {
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, paint)
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, strokePaint)
                    canvas.drawText(labelFor(control), zone.cx, zone.cy + labelPaint.textSize * 0.35f, labelPaint)
                }
            }
        }
    }

    private fun labelFor(control: Control): String = when (control) {
        Control.DPAD_UP -> "▲"; Control.DPAD_DOWN -> "▼"
        Control.DPAD_LEFT -> "◀"; Control.DPAD_RIGHT -> "▶"
        Control.A -> "A"; Control.B -> "B"; Control.X -> "X"; Control.Y -> "Y"
        Control.Z -> "Z"; Control.L -> "L"; Control.R -> "R"
        Control.START -> "START"
        else -> ""
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        layoutDirty = true
    }
}

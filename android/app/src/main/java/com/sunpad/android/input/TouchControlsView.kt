package com.sunpad.android.input

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import com.sunpad.android.GameInputState
import com.sunpad.android.SunPadButtons
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * BellPad-style landscape touch overlay: move stick, camera (C) stick,
 * A/B/X/Y, Z, L, analog R, START, and the three-dot menu. The on-screen
 * D-pad is intentionally omitted; a connected physical controller still
 * supplies its D-pad directly.
 *
 * Layout editing (port of the iOS editor): with [editingLayout] enabled each
 * control can be dragged to a new position (persisted as a normalized origin
 * in "SunPadControlOrigins") and tapped to resize (per-control scale in
 * "SunPadControlSizeScales", 0.6–1.75). The editor bar offers Reset and
 * Done. Positions and sizes survive process death and app restart
 * (SharedPreferences); they are
 * lost only if the user resets the layout, clears app data, or uninstalls.
 */
class TouchControlsView(context: Context) : View(context) {

    interface Listener {
        fun onMenuTap()

        /** Edit mode tapped a control: the activity shows a size slider. */
        fun onResizeRequested(controlId: String, currentScale: Float)
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
            layoutDirty = true
            invalidate()
        }

    /** When true, touch input is suppressed and drags move the layout. */
    var editingLayout: Boolean = false
        set(value) {
            if (field != value) {
                // Leaving edit mode: keep any in-progress drag so Done / a
                // configuration change cannot throw the control back.
                if (!value) persistInProgressEdit()
                field = value
                releaseAll()
                editDrag = null
                selectedControl = null
                layoutDirty = true
                invalidate()
            }
        }

    private val prefs = context.getSharedPreferences("sunpad", Context.MODE_PRIVATE)
    private val origins = loadOrigins()
    private val sizeScales = loadSizeScales()

    private val state = GameInputState()
    private val stateLock = Any()

    private enum class Control {
        MOVE, C, A, B, X, Y, Z, L, R, START, MENU,
    }

    private data class Zone(
        val control: Control,
        var cx: Float = 0f, var cy: Float = 0f, var radius: Float = 0f,
    )

    private val zones = Control.entries.associateWith { Zone(it) }
    private val pointers = HashMap<Int, Control>()
    private val stickOrigins = HashMap<Control, Pair<Float, Float>>()
    private val lastX = HashMap<Int, Float>()
    private val lastY = HashMap<Int, Float>()

    private data class EditDrag(
        val control: Control,
        val grabDx: Float,
        val grabDy: Float,
        val startX: Float,
        val startY: Float,
    )

    private var editDrag: EditDrag? = null
    private var selectedControl: Control? = null

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
    private val editBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 6f
        color = Color.argb(242, 255, 199, 51)
    }
    private val selectedBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 8f
        color = Color.argb(255, 51, 199, 255)
    }
    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.argb(224, 20, 20, 26)
    }
    private val barButtonPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.argb(255, 46, 46, 58)
    }
    private val barTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        typeface = android.graphics.Typeface.DEFAULT_BOLD
        textSize = 30f
    }

    private var layoutDirty = true

    companion object {
        const val ID_MOVE = "move"
        const val ID_C = "c"
        private const val PREF_ORIGINS = "SunPadControlOrigins"
        private const val PREF_SIZE_SCALES = "SunPadControlSizeScales"
        private const val SIZE_MIN = 0.60f
        private const val SIZE_MAX = 1.75f
    }

    // ------------------------------------------------------------------ persistence

    private fun loadOrigins(): MutableMap<String, Pair<Float, Float>> =
        TouchLayoutCodec.decodeOrigins(prefs.getStringSet(PREF_ORIGINS, emptySet()))

    private fun saveAllOrigins() {
        // Rewrite the whole set from the in-memory map. Incremental
        // getStringSet/putStringSet edits are easy to lose (SharedPreferences
        // returns its live set, and a later layout pass would then reload
        // stale positions).
        prefs.edit().putStringSet(PREF_ORIGINS, TouchLayoutCodec.encodeOrigins(origins)).apply()
    }

    private fun loadSizeScales(): MutableMap<String, Float> =
        TouchLayoutCodec.decodeScales(prefs.getStringSet(PREF_SIZE_SCALES, emptySet()), SIZE_MIN, SIZE_MAX)

    private fun saveAllSizeScales() {
        prefs.edit().putStringSet(PREF_SIZE_SCALES, TouchLayoutCodec.encodeScales(sizeScales)).apply()
    }

    fun sizeScaleFor(controlId: String): Float = sizeScales[controlId] ?: 1f

    /** Applies a per-control size scale (0.6–1.75) and persists it. */
    fun setSizeScale(controlId: String, value: Float) {
        sizeScales[controlId] = value.coerceIn(SIZE_MIN, SIZE_MAX)
        saveAllSizeScales()
        layoutDirty = true
        invalidate()
    }

    /** Restores every control position and size to its default. */
    fun resetLayout() {
        prefs.edit()
            .remove(PREF_ORIGINS)
            .remove(PREF_SIZE_SCALES)
            .apply()
        origins.clear()
        sizeScales.clear()
        layoutDirty = true
        invalidate()
    }

    // ------------------------------------------------------------------ layout math

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        layoutDirty = true
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        if (changed) layoutDirty = true
    }

    private fun controlId(control: Control): String? = when (control) {
        Control.MOVE -> ID_MOVE
        Control.C -> ID_C
        Control.A -> "A"
        Control.B -> "B"
        Control.X -> "X"
        Control.Y -> "Y"
        Control.Z -> "Z"
        Control.L -> "L"
        Control.R -> "R"
        Control.START -> "Start"
        else -> null
    }

    /** Center for a control: persisted normalized origin or default. */
    private fun centered(id: String, defaultX: Float, defaultY: Float): Pair<Float, Float> {
        val origin = origins[id]
        return if (origin != null) origin.first * width to origin.second * height
               else defaultX to defaultY
    }

    private fun layoutZones() {
        if (!layoutDirty) return
        layoutDirty = false
        val w = width.toFloat()
        val h = height.toFloat()
        val g = scale
        // A measure/layout pass during a drag must not snap the grabbed
        // control back to its last saved origin — that made buttons look
        // like they refused to move.
        val dragging = editDrag?.control

        if (dragging != Control.MOVE) {
            val moveCenter = centered(ID_MOVE, 0.155f * w, 0.60f * h)
            zones.getValue(Control.MOVE).apply {
                cx = moveCenter.first; cy = moveCenter.second
                radius = 0.105f * w * g * sizeScaleFor(ID_MOVE)
            }
        }
        if (dragging != Control.C) {
            val cCenter = centered(ID_C, 0.585f * w, 0.30f * h)
            zones.getValue(Control.C).apply {
                cx = cCenter.first; cy = cCenter.second
                radius = 0.08925f * w * g * sizeScaleFor(ID_C)
            }
        }

        fun place(control: Control, id: String, dx: Float, dy: Float, baseRadius: Float) {
            if (control == dragging) return
            val center = centered(id, dx, dy)
            zones.getValue(control).apply {
                cx = center.first; cy = center.second
                radius = baseRadius * sizeScaleFor(id)
            }
        }
        place(Control.A, "A", 0.865f * w, 0.60f * h, 0.034f * w * g)
        place(Control.B, "B", 0.795f * w, 0.70f * h, 0.034f * w * g)
        place(Control.X, "X", 0.865f * w, 0.50f * h, 0.034f * w * g)
        place(Control.Y, "Y", 0.935f * w, 0.60f * h, 0.034f * w * g)
        place(Control.Z, "Z", 0.70f * w, 0.33f * h, 0.0364f * w * g)
        place(Control.L, "L", 0.10f * w, 0.09f * h, 0.0448f * w * g)
        place(Control.R, "R", 0.90f * w, 0.09f * h, 0.0448f * w * g)
        place(Control.START, "Start", 0.50f * w, 0.90f * h, 0.042f * w * g)

        // Menu button: top-center, far from both the camera cutout corner
        // and the R/L shoulder buttons, with a generous hit zone.
        zones.getValue(Control.MENU).apply {
            cx = 0.5f * w; cy = 0.08f * h; radius = 0.045f * w * g
        }
    }

    // ------------------------------------------------------------------ touch input

    private fun controlAt(x: Float, y: Float): Control? {
        layoutZones()
        // Sticks first: a touch inside a stick zone is always a stick drag.
        for (c in listOf(Control.MOVE, Control.C)) {
            val z = zones.getValue(c)
            if (hypot(x - z.cx, y - z.cy) <= z.radius + 12f)
                return c
        }
        return zones.entries.firstOrNull { (c, z) ->
            c != Control.MENU && hypot(x - z.cx, y - z.cy) <= z.radius + 12f
        }?.key
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        layoutZones()
        if (editingLayout)
            return onEditTouch(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val idx = if (event.actionMasked == MotionEvent.ACTION_DOWN) 0 else event.actionIndex
                val id = event.getPointerId(idx)
                val x = event.getX(idx); val y = event.getY(idx)
                val menu = zones.getValue(Control.MENU)
                if (hypot(x - menu.cx, y - menu.cy) <= menu.radius + 26f) {
                    listener?.onMenuTap()
                    return true
                }
                val control = controlAt(x, y) ?: return true
                pointers[id] = control
                lastX[id] = x; lastY[id] = y
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
                    val id = pointers.entries.firstOrNull { it.value == control }?.key ?: return
                    val x = lastX[id] ?: return
                    val y = lastY[id] ?: return
                    val dx = x - origin.first
                    val dy = y - origin.second
                    val radius = zone.radius
                    val dist = hypot(dx, dy)
                    val deadZone = radius * 0.10f
                    val nx = if (dist <= deadZone) 0f
                             else (dx / dist).coerceIn(-1f, 1f) *
                                  min(1f, (dist - deadZone) / (radius - deadZone))
                    val ny = if (dist <= deadZone) 0f
                             else (dy / dist).coerceIn(-1f, 1f) *
                                  min(1f, (dist - deadZone) / (radius - deadZone))
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

    // ------------------------------------------------------------------ layout editing

    private fun editableControlAt(x: Float, y: Float): Control? {
        layoutZones()
        for (control in listOf(
                Control.MOVE, Control.C, Control.A, Control.B, Control.X,
                Control.Y, Control.Z, Control.L, Control.R, Control.START)) {
            val zone = zones.getValue(control)
            if (hypot(x - zone.cx, y - zone.cy) <= zone.radius + 16f)
                return control
        }
        return null
    }

    private val editorBar = RectF()
    private val resetButton = RectF()
    private val doneButton = RectF()

    private fun layoutEditorBar() {
        val w = width.toFloat()
        val h = height.toFloat()
        val barWidth = min(560f, w - 24f)
        val barHeight = 64f
        val left = (w - barWidth) * 0.5f
        val top = h - barHeight - 16f
        editorBar.set(left, top, left + barWidth, top + barHeight)
        resetButton.set(left + 12f, top + 12f, left + 132f, top + barHeight - 12f)
        doneButton.set(left + barWidth - 112f, top + 12f, left + barWidth - 12f,
                       top + barHeight - 12f)
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun onEditTouch(event: MotionEvent): Boolean {
        layoutEditorBar()
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val x = event.x; val y = event.y
                val menu = zones.getValue(Control.MENU)
                if (hypot(x - menu.cx, y - menu.cy) <= menu.radius + 26f) {
                    // The three-dot menu stays available while editing.
                    listener?.onMenuTap()
                    return true
                }
                // Only the Reset / Done buttons consume the bar, so controls
                // near the bottom edge remain draggable.
                if (resetButton.contains(x, y)) {
                    resetLayout()
                    return true
                }
                if (doneButton.contains(x, y)) {
                    editingLayout = false
                    return true
                }
                val control = editableControlAt(x, y) ?: return true
                selectedControl = control
                val zone = zones.getValue(control)
                editDrag = EditDrag(control, x - zone.cx, y - zone.cy, x, y)
                invalidate()
            }
            MotionEvent.ACTION_MOVE -> {
                val drag = editDrag ?: return true
                val zone = zones.getValue(drag.control)
                var cx = (event.x - drag.grabDx).coerceIn(zone.radius, width - zone.radius)
                var cy = (event.y - drag.grabDy).coerceIn(zone.radius, height - zone.radius)
                zone.cx = cx.coerceIn(zone.radius, width - zone.radius)
                zone.cy = cy.coerceIn(zone.radius, height - zone.radius)
                invalidate()
            }
            MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val drag = editDrag ?: return true
                val zone = zones.getValue(drag.control)
                val id = controlId(drag.control)
                val moved = hypot(event.x - drag.startX, event.y - drag.startY)
                editDrag = null
                if (moved < 12f) {
                    // Tap: snap back (in case the finger jiggled) and resize.
                    layoutDirty = true
                    if (id != null)
                        listener?.onResizeRequested(id, sizeScaleFor(id))
                } else {
                    persistOrigin(drag.control, zone.cx, zone.cy)
                }
                invalidate()
            }
        }
        return true
    }

    private fun persistOrigin(control: Control, cx: Float, cy: Float) {
        if (width <= 0 || height <= 0) return
        val normalized = (cx / width).coerceIn(0f, 1f) to (cy / height).coerceIn(0f, 1f)
        val id = controlId(control) ?: return
        origins[id] = normalized
        saveAllOrigins()
    }

    /** Writes the control currently under the finger, if any. */
    fun persistInProgressEdit() {
        val drag = editDrag ?: return
        val zone = zones.getValue(drag.control)
        persistOrigin(drag.control, zone.cx, zone.cy)
    }

    // ------------------------------------------------------------------ drawing

    private fun labelFor(control: Control): String = when (control) {
        Control.A -> "A"; Control.B -> "B"; Control.X -> "X"; Control.Y -> "Y"
        Control.Z -> "Z"; Control.L -> "L"; Control.R -> "R"
        Control.START -> "START"
        else -> ""
    }

    private fun isEditable(control: Control): Boolean = when (control) {
        Control.MOVE, Control.C, Control.A, Control.B,
        Control.X, Control.Y, Control.Z, Control.L, Control.R, Control.START -> true
        else -> false
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        layoutZones()
        val alpha = (opacity * 255).toInt().coerceIn(0, 255)
        fillPaint.alpha = alpha
        strokePaint.alpha = (alpha * 0.9f).toInt()
        labelPaint.textSize = zones.getValue(Control.A).radius * 1.25f

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
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, paint)
                    val dot = zone.radius * 0.28f
                    for (i in -1..1)
                        canvas.drawCircle(zone.cx + i * zone.radius * 0.5f, zone.cy, dot, labelPaint)
                }
                else -> {
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, paint)
                    canvas.drawCircle(zone.cx, zone.cy, zone.radius, strokePaint)
                    canvas.drawText(labelFor(control), zone.cx,
                                    zone.cy + labelPaint.textSize * 0.35f, labelPaint)
                }
            }
        }

        if (editingLayout) {
            // Selection borders over every editable control.
            for ((control, zone) in zones) {
                if (!isEditable(control)) continue
                val selected = control == selectedControl
                canvas.drawCircle(zone.cx, zone.cy, zone.radius + 6f,
                                  if (selected) selectedBorderPaint else editBorderPaint)
            }
            drawEditorBar(canvas)
        }
    }

    private fun drawEditorBar(canvas: Canvas) {
        layoutEditorBar()
        canvas.drawRoundRect(editorBar, 16f, 16f, barPaint)
        canvas.drawRoundRect(resetButton, 10f, 10f, barButtonPaint)
        canvas.drawRoundRect(doneButton, 10f, 10f, barButtonPaint)
        barTextPaint.textSize = 26f
        canvas.drawText("Drag controls • tap to resize",
                        editorBar.centerX(), editorBar.centerY() + 9f, barTextPaint)
        barTextPaint.textSize = 24f
        canvas.drawText("Reset", resetButton.centerX(), resetButton.centerY() + 8f, barTextPaint)
        canvas.drawText("Done", doneButton.centerX(), doneButton.centerY() + 8f, barTextPaint)
    }
}

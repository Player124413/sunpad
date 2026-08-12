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
 * grouped D-pad, A/B/X/Y, Z, L, analog R, START, and the three-dot menu.
 *
 * Layout editing (port of the iOS editor): with [editingLayout] enabled each
 * control can be dragged to a new position (persisted as a normalized origin
 * in "SunPadControlOrigins" / "SunPadExperimentalDPadOriginKey") and tapped
 * to resize (per-control scale in "SunPadControlSizeScales" /
 * "SunPadExperimentalDPadScaleKey", 0.6–1.75). The D-pad moves and resizes
 * as a single group. The editor bar offers Reset and Done.
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
        MOVE, C, DPAD_GROUP, DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT,
        A, B, X, Y, Z, L, R, START, MENU,
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
        const val ID_DPAD_GROUP = "DPadGroup"
        private const val PREF_ORIGINS = "SunPadControlOrigins"
        private const val PREF_SIZE_SCALES = "SunPadControlSizeScales"
        private const val PREF_DPAD_ORIGIN = "SunPadExperimentalDPadOriginKey"
        private const val PREF_DPAD_SCALE = "SunPadExperimentalDPadScaleKey"
        private const val SIZE_MIN = 0.60f
        private const val SIZE_MAX = 1.75f
    }

    // ------------------------------------------------------------------ persistence

    private fun loadOrigins(): MutableMap<String, Pair<Float, Float>> {
        val out = HashMap<String, Pair<Float, Float>>()
        prefs.getStringSet(PREF_ORIGINS, emptySet())?.forEach { raw ->
            val parts = raw.split("=")
            if (parts.size == 2) {
                val xy = parts[1].split(",")
                if (xy.size == 2) {
                    val x = xy[0].toFloatOrNull() ?: return@forEach
                    val y = xy[1].toFloatOrNull() ?: return@forEach
                    out[parts[0]] = x.coerceIn(0f, 1f) to y.coerceIn(0f, 1f)
                }
            }
        }
        return out
    }

    private fun saveOrigin(id: String, normalized: Pair<Float, Float>) {
        val set = prefs.getStringSet(PREF_ORIGINS, emptySet())!!.toMutableSet()
        set.removeAll { it.startsWith("$id=") }
        set.add("$id=${normalized.first},${normalized.second}")
        prefs.edit().putStringSet(PREF_ORIGINS, set).apply()
    }

    private fun loadSizeScales(): MutableMap<String, Float> {
        val out = HashMap<String, Float>()
        prefs.getStringSet(PREF_SIZE_SCALES, emptySet())?.forEach { raw ->
            val parts = raw.split("=")
            if (parts.size == 2) {
                parts[1].toFloatOrNull()?.let {
                    out[parts[0]] = it.coerceIn(SIZE_MIN, SIZE_MAX)
                }
            }
        }
        return out
    }

    private fun saveSizeScale(id: String, value: Float) {
        val set = prefs.getStringSet(PREF_SIZE_SCALES, emptySet())!!.toMutableSet()
        set.removeAll { it.startsWith("$id=") }
        set.add("$id=${value.coerceIn(SIZE_MIN, SIZE_MAX)}")
        prefs.edit().putStringSet(PREF_SIZE_SCALES, set).apply()
    }

    private fun dpadOrigin(): Pair<Float, Float>? {
        val raw = prefs.getString(PREF_DPAD_ORIGIN, null) ?: return null
        val xy = raw.split(",")
        if (xy.size != 2) return null
        val x = xy[0].toFloatOrNull() ?: return null
        val y = xy[1].toFloatOrNull() ?: return null
        return x.coerceIn(0f, 1f) to y.coerceIn(0f, 1f)
    }

    private var dpadScaleCache: Float =
        prefs.getFloat(PREF_DPAD_SCALE, 1f).coerceIn(SIZE_MIN, SIZE_MAX)

    private fun dpadScale(): Float = dpadScaleCache

    fun sizeScaleFor(controlId: String): Float = sizeScales[controlId] ?: 1f

    /** Applies a per-control size scale (0.6–1.75) and persists it. */
    fun setSizeScale(controlId: String, value: Float) {
        val clamped = value.coerceIn(SIZE_MIN, SIZE_MAX)
        if (controlId == ID_DPAD_GROUP) {
            dpadScaleCache = clamped
            prefs.edit().putFloat(PREF_DPAD_SCALE, clamped).apply()
        } else {
            sizeScales[controlId] = clamped
            saveSizeScale(controlId, clamped)
        }
        layoutDirty = true
        invalidate()
    }

    /** Restores every control position and size to its default. */
    fun resetLayout() {
        prefs.edit()
            .remove(PREF_ORIGINS)
            .remove(PREF_SIZE_SCALES)
            .remove(PREF_DPAD_ORIGIN)
            .remove(PREF_DPAD_SCALE)
            .apply()
        origins.clear()
        sizeScales.clear()
        dpadScaleCache = 1f
        layoutDirty = true
        invalidate()
    }

    // ------------------------------------------------------------------ layout math

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        layoutDirty = true
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        layoutDirty = true
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

        val moveCenter = centered(ID_MOVE, 0.155f * w, 0.60f * h)
        zones.getValue(Control.MOVE).apply {
            cx = moveCenter.first; cy = moveCenter.second
            radius = 0.105f * w * g * sizeScaleFor(ID_MOVE)
        }
        val cCenter = centered(ID_C, 0.585f * w, 0.30f * h)
        zones.getValue(Control.C).apply {
            cx = cCenter.first; cy = cCenter.second
            radius = 0.08925f * w * g * sizeScaleFor(ID_C)
        }

        val dHalf = 0.060f * w * g * dpadScale()
        val dpadSaved = dpadOrigin()
        // D-pad sits right of the move stick (same left cluster but further
        // along X) so their touch zones never overlap.
        val groupCenter = if (dpadSaved != null) dpadSaved.first * w to dpadSaved.second * h
                          else 0.30f * w to 0.84f * h
        zones.getValue(Control.DPAD_UP).apply { cx = groupCenter.first; cy = groupCenter.second - dHalf; radius = dHalf }
        zones.getValue(Control.DPAD_DOWN).apply { cx = groupCenter.first; cy = groupCenter.second + dHalf; radius = dHalf }
        zones.getValue(Control.DPAD_LEFT).apply { cx = groupCenter.first - dHalf; cy = groupCenter.second; radius = dHalf }
        zones.getValue(Control.DPAD_RIGHT).apply { cx = groupCenter.first + dHalf; cy = groupCenter.second; radius = dHalf }
        zones.getValue(Control.DPAD_GROUP).apply {
            cx = groupCenter.first; cy = groupCenter.second
            radius = 1.5f * dHalf
        }

        fun place(control: Control, id: String, dx: Float, dy: Float, baseRadius: Float) {
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
        // Sticks first: if the touch is inside a stick's zone, it is a
        // stick drag even if it also overlaps the D-pad cluster.
        for (c in listOf(Control.MOVE, Control.C)) {
            val z = zones.getValue(c)
            if (hypot(x - z.cx, y - z.cy) <= z.radius + 12f)
                return c
        }
        return zones.entries.firstOrNull { (c, z) ->
            c != Control.MENU && c != Control.DPAD_GROUP &&
                hypot(x - z.cx, y - z.cy) <= z.radius + 12f
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
        // Individual controls first; D-pad buttons belong to the group.
        for (control in listOf(
                Control.MOVE, Control.C, Control.A, Control.B, Control.X,
                Control.Y, Control.Z, Control.L, Control.R, Control.START)) {
            val zone = zones.getValue(control)
            if (hypot(x - zone.cx, y - zone.cy) <= zone.radius + 16f)
                return control
        }
        val group = zones.getValue(Control.DPAD_GROUP)
        if (hypot(x - group.cx, y - group.cy) <= group.radius + 16f)
            return Control.DPAD_GROUP
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
                if (editorBar.contains(x, y)) {
                    if (resetButton.contains(x, y)) {
                        resetLayout()
                        return true
                    }
                    if (doneButton.contains(x, y)) {
                        editingLayout = false
                        return true
                    }
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
                // Never allow the sticks and the D-pad group to overlap:
                // otherwise a saved layout can make the stick stick to the
                // arrows during gameplay.
                val others = when (drag.control) {
                    Control.MOVE, Control.C ->
                        listOf(zones.getValue(Control.DPAD_GROUP))
                    Control.DPAD_GROUP ->
                        listOf(zones.getValue(Control.MOVE), zones.getValue(Control.C))
                    else -> emptyList()
                }
                val minDist = zone.radius + 24f
                for (o in others) {
                    val d = hypot(cx - o.cx, cy - o.cy)
                    if (d < minDist && d > 0.001f) {
                        val push = (minDist - d) / d
                        cx += (cx - o.cx) * push
                        cy += (cy - o.cy) * push
                    }
                }
                zone.cx = cx.coerceIn(zone.radius, width - zone.radius)
                zone.cy = cy.coerceIn(zone.radius, height - zone.radius)
                invalidate()
            }
            MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val drag = editDrag ?: return true
                editDrag = null
                val zone = zones.getValue(drag.control)
                val isGroup = drag.control == Control.DPAD_GROUP
                val id = controlId(drag.control)
                val moved = hypot(event.x - drag.startX, event.y - drag.startY)
                if (moved < 12f) {
                    // Tap: request resize for the selected control.
                    if (isGroup)
                        listener?.onResizeRequested(ID_DPAD_GROUP, dpadScale())
                    else if (id != null)
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
        if (control == Control.DPAD_GROUP) {
            prefs.edit().putString(PREF_DPAD_ORIGIN, "${normalized.first},${normalized.second}").apply()
        } else {
            val id = controlId(control) ?: return
            saveOrigin(id, normalized)
        }
    }

    // ------------------------------------------------------------------ drawing

    private fun labelFor(control: Control): String = when (control) {
        Control.DPAD_UP -> "▲"; Control.DPAD_DOWN -> "▼"
        Control.DPAD_LEFT -> "◀"; Control.DPAD_RIGHT -> "▶"
        Control.A -> "A"; Control.B -> "B"; Control.X -> "X"; Control.Y -> "Y"
        Control.Z -> "Z"; Control.L -> "L"; Control.R -> "R"
        Control.START -> "START"
        else -> ""
    }

    private val dpadButtons = setOf(
        Control.DPAD_UP, Control.DPAD_DOWN, Control.DPAD_LEFT, Control.DPAD_RIGHT,
    )

    private fun isEditable(control: Control): Boolean = when (control) {
        Control.MOVE, Control.C, Control.DPAD_GROUP, Control.A, Control.B,
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
            if (control == Control.DPAD_GROUP) continue
            // In edit mode the D-pad renders as its group container only
            // (the buttons are laid out from the saved group origin).
            if (editingLayout && control in dpadButtons) continue
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
            val group = zones.getValue(Control.DPAD_GROUP)
            for ((control, zone) in zones) {
                if (!isEditable(control) || control == Control.DPAD_GROUP) continue
                val selected = control == selectedControl
                canvas.drawCircle(zone.cx, zone.cy, zone.radius + 6f,
                                  if (selected) selectedBorderPaint else editBorderPaint)
            }
            val selected = selectedControl == Control.DPAD_GROUP
            canvas.drawCircle(group.cx, group.cy, group.radius + 6f,
                              if (selected) selectedBorderPaint else editBorderPaint)
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

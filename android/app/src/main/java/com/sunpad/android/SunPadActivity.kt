package com.sunpad.android

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.SeekBar
import android.view.InputDevice
import android.widget.TextView
import android.widget.Toast
import com.sunpad.android.input.GamepadReader
import com.sunpad.android.input.TouchControlsView
import java.util.Locale
import kotlin.math.roundToInt

/**
 * SunPad Android main activity: hosts the game Surface handed to the Vulkan
 * backend, the BellPad-style touch overlay, Android gamepad merging, the
 * user-owned game-data import flow, and the settings menu.
 */
class SunPadActivity : Activity(), SurfaceHolder.Callback {

    private lateinit var importer: GameDataImporter
    private lateinit var rootView: FrameLayout
    private lateinit var surfaceView: SurfaceView
    private lateinit var controls: TouchControlsView
    private lateinit var hud: TextView
    private lateinit var gamepad: GamepadReader

    private val merged = GameInputState()
    private val touchState = GameInputState()

    private var surfaceReady = false
    private var started = false
    private var startPending = false
    private var lastSurfaceW = 0
    private var lastSurfaceH = 0
    private var hudVisible = false
    private var lastHudUpdate = 0L
    private val uiHandler = Handler(Looper.getMainLooper())
    private lateinit var statusView: TextView

    private val prefs by lazy { getSharedPreferences("sunpad", MODE_PRIVATE) }

    // ------------------------------------------------------------------ lifecycle

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        importer = GameDataImporter(this)
        gamepad = GamepadReader(this)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setImmersive()

        rootView = FrameLayout(this)
        surfaceView = SurfaceView(this)
        surfaceView.holder.setFormat(PixelFormat.RGBA_8888)
        surfaceView.holder.addCallback(this)
        rootView.addView(surfaceView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        controls = TouchControlsView(this)
        controls.listener = object : TouchControlsView.Listener {
            override fun onMenuTap() {
                // Haptic feedback so a tap on the menu button is always
                // visible (also a diagnostic: vibration == touch reached it).
                controls.performHapticFeedback(
                    android.view.HapticFeedbackConstants.VIRTUAL_KEY)
                android.util.Log.i("SunPad", "menu button tapped")
                showMenu()
            }

            override fun onResizeRequested(controlId: String, currentScale: Float) {
                showResizeDialog(controlId, currentScale)
            }
        }
        rootView.addView(controls, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        hud = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 13f
            setShadowLayer(3f, 1f, 1f, Color.BLACK)
            visibility = View.GONE
        }
        rootView.addView(hud, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.START).apply { topMargin = dp(24); leftMargin = dp(8) })

        statusView = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            setShadowLayer(4f, 1f, 1f, Color.BLACK)
            gravity = Gravity.CENTER
            visibility = View.GONE
        }
        rootView.addView(statusView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER))

        setContentView(rootView)
        gamepad.attach(rootView)

        applyPrefsToControls()
        DiagnosticLog.ensurePublicFolder(this)
        // Native logs must land in the private file: Copy diagnostic log
        // reads that one first. The public sunpad.log still gets Java lines.
        SunPadNative.setCrashLogPath(DiagnosticLog.privateFile(this).absolutePath)
        if (prefs.getBoolean("bootInProgress", false)) {
            prefs.edit().putBoolean("preferOgl", true).putBoolean("bootInProgress", false).commit()
            DiagnosticLog.append(this, "Last session died during boot; preferring OpenGL ES")
        }
        val backend = if (prefs.getBoolean("preferOgl", true)) "OGL" else "Vulkan"
        SunPadNative.setPreferredBackend(backend)
        DiagnosticLog.append(this, "SunPad activity created. native=${SunPadNative.available} backend=$backend ${SunPadNative.loadError ?: ""}")
        showPreviousCrashIfAny()
        if (!SunPadNative.available) {
            showStartError(
                "Native library failed to load.\n\n${SunPadNative.loadError ?: ""}\n\n" +
                    "This APK only contains arm64 code. It will not run on an x86 emulator.")
        }
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    override fun onResume() {
        super.onResume()
        setImmersive()
        SunPadNative.resume()
    }

    override fun onPause() {
        // Flush a mid-drag layout edit so a process death cannot lose it.
        controls.persistInProgressEdit()
        SunPadNative.pause()
        super.onPause()
    }

    override fun onDestroy() {
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        gamepad.detach(rootView)
        SunPadNative.stop()
        super.onDestroy()
    }

    // ------------------------------------------------------------------ surface

    override fun surfaceCreated(holder: SurfaceHolder) {
        surfaceReady = true
        SunPadNative.setSurface(holder.surface)
        if (!started || startPending) {
            startGameIfReady()
        } else {
            // Surface recreated (rotation / resume): the swapchain is rebuilt
            // through the presenter, so unpause the runtime.
            SunPadNative.resume()
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {
        // The nav bar / cutout toggles width by ~100–130 px (2522↔2395).
        // Rebuilding the swapchain on every oscillation aborts Adreno.
        if (started && lastSurfaceW > 0 && lastSurfaceH == h &&
            kotlin.math.abs(w - lastSurfaceW) < 160) {
            DiagnosticLog.append(this, "surfaceChanged ${w}x${h} ignored (nav-bar jitter)")
            return
        }
        lastSurfaceW = w
        lastSurfaceH = h
        DiagnosticLog.append(this, "surfaceChanged ${w}x${h} format=$format")
        SunPadNative.setSurface(holder.surface)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        surfaceReady = false
        SunPadNative.pause()
        controls.releaseAll()
    }

    // ------------------------------------------------------------------ game start

    private fun startGameIfReady() {
        if (started) return
        if (!importer.hasActiveGame() || !importer.ensureModule()) {
            startPending = false
            showSetupDialog()
            return
        }
        if (!surfaceReady) {
            startPending = true
            showStatus("Waiting for the screen…")
            return
        }
        if (!SunPadNative.available) {
            showStartError(SunPadNative.loadError ?: "Native library is not loaded.")
            return
        }
        val moduleError = importer.validateModuleFile(importer.moduleFile)
        if (moduleError != null) {
            showStartError(moduleError)
            showSetupDialog()
            return
        }
        startPending = false
        started = true
        importer.userDirectory.mkdirs()
        importer.ensureDolphinSys()
        DiagnosticLog.append(
            this,
            "starting ISO=${importer.activeImage.length()} " +
                "module=${importer.moduleFile.length()} " +
                "surface=${lastSurfaceW}x${lastSurfaceH}",
        )
        prefs.edit().putBoolean("bootInProgress", true).commit()
        showStatus("Starting game…")
        Thread {
            val error = try {
                SunPadNative.start(
                    importer.gameRoot.absolutePath,
                    importer.discImagePath,
                    importer.modulePath,
                    importer.userDirectoryPath,
                )
            } catch (t: Throwable) {
                android.util.Log.e("SunPad", "start threw", t)
                t.message ?: t.javaClass.simpleName
            }
            uiHandler.post {
                if (error != null) {
                    started = false
                    prefs.edit().putBoolean("bootInProgress", false).apply()
                    hideStatus()
                    showStartError(error)
                    showSetupDialog()
                } else {
                    hideStatus()
                    uiHandler.postDelayed({
                        if (isFinishing || isDestroyed) return@postDelayed
                        if (SunPadNative.isRunning()) {
                            prefs.edit().putBoolean("bootInProgress", false).apply()
                        } else if (started) {
                            started = false
                            prefs.edit().putBoolean("bootInProgress", false).apply()
                            showStartError(
                                "The game stopped right after start. " +
                                    "Use ••• → Copy diagnostic log and send it.")
                        }
                    }, 2500)
                }
            }
        }.start()
    }

    private fun showStatus(message: String) {
        if (isFinishing || isDestroyed) return
        statusView.text = message
        statusView.visibility = View.VISIBLE
    }

    private fun hideStatus() {
        statusView.visibility = View.GONE
    }

    private fun showStartError(message: String) {
        if (isFinishing || isDestroyed) return
        DiagnosticLog.append(this, "start error: $message")
        AlertDialog.Builder(this)
            .setTitle("Could not start the game")
            .setMessage(message)
            .setNeutralButton("Copy log") { _, _ -> copyLogToClipboard() }
            .setPositiveButton("OK", null)
            .show()
    }

    private fun showPreviousCrashIfAny() {
        val text = DiagnosticLog.read(this)
        if (text.isBlank() || text == "(no log yet)") return
        if (!text.contains("Uncaught") && !text.contains("NATIVE CRASH") &&
            !text.contains("died during boot"))
            return
        AlertDialog.Builder(this)
            .setTitle("SunPad closed last time")
            .setMessage(text.take(1500))
            .setNeutralButton("Copy log") { _, _ -> copyLogToClipboard() }
            .setPositiveButton("OK", null)
            .show()
    }

    private fun copyLogToClipboard() {
        DiagnosticLog.ensurePublicFolder(this)
        val text = DiagnosticLog.copyToClipboard(this)
        val publicPath = DiagnosticLog.publicFile(this)?.absolutePath
        Toast.makeText(
            this,
            if (publicPath != null)
                "Log copied. Also saved to:\n$publicPath"
            else
                "Log copied (${text.length} chars).",
            Toast.LENGTH_LONG,
        ).show()
    }

    private fun showSetupDialog() {
        if (isFinishing || isDestroyed) return
        val items = ArrayList<String>()
        val actions = ArrayList<() -> Unit>()
        if (!importer.hasActiveGame()) {
            items.add("Import game data (GMSE01 ISO/GCM)…")
            actions.add { pickImage() }
        }
        if (!importer.ensureModule()) {
            items.add("Set game module (gGMSE01_recomp.so)…")
            actions.add { pickModule() }
        }
        if (importer.hasActiveGame()) {
            items.add("Remove imported game data")
            actions.add {
                importer.removeGameData()
                showSetupDialog()
            }
        }
        items.add("Quit")
        actions.add { finish() }
        val hasIso = importer.hasActiveGame()
        val hasModule = importer.ensureModule()
        val missing = buildString {
            if (!hasIso && !hasModule)
                append("SunPad needs TWO files. Both are required.\n\n")
            else if (!hasIso)
                append("ISO is still missing.\n\n")
            else if (!hasModule)
                append("The game module is still missing.\n\n")
        }
        AlertDialog.Builder(this)
            .setTitle(
                when {
                    started -> "SunPad"
                    hasIso && hasModule -> "SunPad"
                    else -> "SunPad — two files required"
                })
            .setMessage(
                if (started) ""
                else missing +
                     "1) ISO / GCM — Super Mario Sunshine USA Rev 0 (GMSE01), " +
                     "about 1.4 GB. This is the disc image: levels, graphics, audio.\n" +
                     "   Tap \"Import game data (GMSE01 ISO/GCM)…\" and pick that file.\n\n" +
                     "2) Module — gGMSE01_recomp.so built for Android arm64. " +
                     "This is NOT the ISO and NOT an iOS .dylib.\n" +
                     "   Tap \"Set game module (gGMSE01_recomp.so)…\" if it is not " +
                     "already bundled in this APK.\n\n" +
                     "SunPad never downloads either file. You supply your own " +
                     "legally obtained disc image.")
            .setItems(items.toTypedArray()) { _, which -> actions[which]() }
            // Только явный выбор "Quit" закрывает приложение; случайное
            // нажатие мимо диалога или Back просто закрывает диалог.
            .show()
    }

    private fun openFilePicker(requestCode: Int) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/octet-stream", "*/*"))
        }
        // Some ROMs lack a DocumentsUI provider; fall back to the classic
        // chooser (ACTION_GET_CONTENT) so the file manager always opens.
        if (intent.resolveActivity(packageManager) != null) {
            startActivityForResult(intent, requestCode)
            return
        }
        val fallback = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        if (fallback.resolveActivity(packageManager) != null) {
            startActivityForResult(fallback, requestCode)
            return
        }
        Toast.makeText(this, "No file picker is available on this device", Toast.LENGTH_LONG).show()
    }

    private fun pickImage() = openFilePicker(REQUEST_IMAGE)

    private fun pickModule() = openFilePicker(REQUEST_MODULE)

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK || data?.data == null) {
            if (!started) showSetupDialog()
            return
        }
        val uri = data.data!!
        when (requestCode) {
            REQUEST_IMAGE -> importImage(uri)
            REQUEST_MODULE -> importModule(uri)
        }
    }

    private fun importImage(uri: android.net.Uri) {
        val dialog = AlertDialog.Builder(this)
            .setTitle("Importing game data")
            .setMessage("Copying…")
            .setCancelable(false)
            .show()
        Thread {
            val copyError = importer.copyAndValidate(uri) { fraction ->
                uiHandler.post {
                    dialog.setMessage("Copying… ${(fraction * 100).toInt()}%")
                }
            }
            if (copyError != null) {
                uiHandler.post {
                    dialog.dismiss()
                    Toast.makeText(this, copyError, Toast.LENGTH_LONG).show()
                    showSetupDialog()
                }
                return@Thread
            }
            var lastStatus = ""
            val extractError = importer.extractAndActivate { status, fraction ->
                if (status != lastStatus) {
                    lastStatus = status
                    uiHandler.post { dialog.setMessage("Extracting… $status") }
                }
                uiHandler.post { dialog.setMessage("Extracting… ${(fraction * 100).toInt()}%") }
            }
            uiHandler.post {
                dialog.dismiss()
                if (extractError != null) {
                    Toast.makeText(this, extractError, Toast.LENGTH_LONG).show()
                } else {
                    Toast.makeText(this, "Game data ready.", Toast.LENGTH_SHORT).show()
                    showStatus("Game data ready. Starting…")
                }
                // The file picker destroys the SurfaceView. Wait for
                // surfaceCreated if needed instead of starting into a null
                // window (that used to crash right after a successful import).
                startPending = true
                startGameIfReady()
            }
        }.start()
    }

    private fun importModule(uri: android.net.Uri) {
        showStatus("Installing module…")
        Thread {
            val error = importer.importModule(uri)
            uiHandler.post {
                hideStatus()
                if (error != null) {
                    showStartError(error)
                    if (!started) showSetupDialog()
                    return@post
                }
                Toast.makeText(this, "Module installed (gGMSE01_recomp.so).", Toast.LENGTH_SHORT).show()
                if (started) {
                    AlertDialog.Builder(this)
                        .setTitle("Module installed")
                        .setMessage("The new module is used the next time the game starts. Close and reopen SunPad to apply it.")
                        .setPositiveButton("OK", null)
                        .show()
                } else {
                    startPending = true
                    startGameIfReady()
                }
            }
        }.start()
    }

    // ------------------------------------------------------------------ menu

    private fun showMenu() {
        if (isFinishing || isDestroyed) return
        // An AlertDialog is used instead of a PopupMenu: PopupMenu can fail
        // to appear over the fullscreen SurfaceView / immersive mode.
        val items = ArrayList<String>()
        val actions = ArrayList<() -> Unit>()

        items.add("Render scale: ${prefs.getInt("scale", 1)}×")
        actions.add { cycleRenderScale(); showMenu() }

        items.add("Aspect ratio")
        actions.add { pickAspect() }

        items.add("Control opacity…")
        actions.add {
            showSeekDialog("Control opacity", 25..90, prefs.getInt("opacity", 55)) {
                controls.opacity = it / 100f
                prefs.edit().putInt("opacity", it).apply()
            }
        }

        items.add("Control size…")
        actions.add {
            showSeekDialog("Control size", 60..140, prefs.getInt("size", 100)) {
                controls.scale = it / 100f
                prefs.edit().putInt("size", it).apply()
            }
        }

        items.add(if (prefs.getBoolean("modernCStick", false))
            "Modern C-stick: ON" else "Modern C-stick: OFF")
        actions.add {
            val on = !prefs.getBoolean("modernCStick", false)
            prefs.edit().putBoolean("modernCStick", on).apply()
            SunPadNative.setModernCStick(on)
            showMenu()
        }

        items.add("Edit touch layout…")
        actions.add {
            controls.editingLayout = true
            Toast.makeText(this, "Drag controls • tap one to resize", Toast.LENGTH_SHORT).show()
        }

        items.add("Reset touch layout…")
        actions.add { confirmResetLayout() }

        items.add("Controller button mapping…")
        actions.add { showMappingDialog() }

        items.add(if (hudVisible) "Hide diagnostics" else "Show diagnostics")
        actions.add { toggleHud() }

        items.add("Import game data (GMSE01 ISO/GCM)…")
        actions.add { pickImage() }

        items.add("Import module (gGMSE01_recomp.so)…")
        actions.add { pickModule() }

        items.add(
            if (prefs.getBoolean("preferOgl", true)) "Renderer: OpenGL ES"
            else "Renderer: Vulkan")
        actions.add {
            val ogl = !prefs.getBoolean("preferOgl", true)
            prefs.edit().putBoolean("preferOgl", ogl).apply()
            SunPadNative.setPreferredBackend(if (ogl) "OGL" else "Vulkan")
            Toast.makeText(
                this,
                if (ogl) "OpenGL ES on next start (close and reopen)"
                else "Vulkan on next start (close and reopen)",
                Toast.LENGTH_LONG,
            ).show()
        }

        items.add("Copy diagnostic log")
        actions.add { copyLogToClipboard() }

        items.add("Quit")
        actions.add { finish() }

        try {
            AlertDialog.Builder(this)
                .setTitle("SunPad")
                .setItems(items.toTypedArray()) { _, which ->
                    if (which in actions.indices) actions[which]()
                }
                .setNegativeButton("Close", null)
                .show()
        } catch (e: Exception) {
            android.util.Log.e("SunPad", "menu failed", e)
            Toast.makeText(this, "Menu error: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private fun cycleRenderScale() {
        val next = (prefs.getInt("scale", 1) % 4) + 1
        prefs.edit().putInt("scale", next).apply()
        SunPadNative.setRenderScale(next)
    }

    private fun pickAspect() {
        val modes = arrayOf("Original 4:3", "Widescreen 16:9", "Fill screen")
        val current = prefs.getInt("aspect", 0)
        AlertDialog.Builder(this)
            .setTitle("Aspect ratio")
            .setSingleChoiceItems(modes, current) { _, which ->
                prefs.edit().putInt("aspect", which).apply()
                SunPadNative.setAspectRatioMode(which)
            }
            .setNegativeButton("Close", null)
            .show()
    }

    private fun showSeekDialog(
        title: String, range: IntRange, current: Int, onChange: (Int) -> Unit,
    ) {
        val slider = SeekBar(this).apply {
            min = range.first
            max = range.last
            progress = current.coerceIn(range)
        }
        val pad = dp(24)
        // AlertDialog.Builder has no 5-argument setView overload in the
        // Kotlin binding; wrap the slider with padding instead.
        val container = FrameLayout(this).apply {
            setPadding(pad, pad / 2, pad, 0)
            addView(slider, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT))
        }
        AlertDialog.Builder(this)
            .setTitle(title)
            .setView(container)
            .setPositiveButton("OK", null)
            .show()
        slider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, v: Int, fromUser: Boolean) {
                if (fromUser) onChange(v)
            }
            override fun onStartTrackingTouch(sb: SeekBar?) {}
            override fun onStopTrackingTouch(sb: SeekBar?) {}
        })
    }

    private fun toggleHud() {
        hudVisible = !hudVisible
        hud.visibility = if (hudVisible) View.VISIBLE else View.GONE
        if (!hudVisible) hud.text = ""
    }

    private fun applyPrefsToControls() {
        controls.opacity = prefs.getInt("opacity", 55) / 100f
        controls.scale = prefs.getInt("size", 100) / 100f
        SunPadNative.setModernCStick(prefs.getBoolean("modernCStick", false))
        SunPadNative.setRenderScale(prefs.getInt("scale", 1))
        SunPadNative.setAspectRatioMode(prefs.getInt("aspect", 0))
    }

    // ------------------------------------------------------------------ input loop

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (isFinishing || isDestroyed) return
            try {
                publishInput()
                if (hudVisible && frameTimeNanos - lastHudUpdate > 500_000_000L) {
                    lastHudUpdate = frameTimeNanos
                    hud.text = String.format(
                        Locale.US, "%.1f FPS  %.2f×  %s",
                        SunPadNative.currentFPS(),
                        SunPadNative.currentSpeed(),
                        SunPadNative.efbResolution())
                }
            } catch (e: Exception) {
                // Не ронять приложение из-за ошибки одного кадра.
                android.util.Log.e("SunPad", "frame error", e)
            }
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    private fun publishInput() {
        merged.reset()
        controls.snapshot(touchState)
        merged.copyFrom(touchState)
        gamepad.merge(merged)
        SunPadNative.publishInput(merged)
    }


    // ------------------------------------------------------------------ layout editing

    private fun confirmResetLayout() {
        AlertDialog.Builder(this)
            .setTitle("Reset Touch Control Layout?")
            .setMessage("All control positions and sizes, including the grouped D-pad, return to their defaults.")
            .setPositiveButton("Reset") { _, _ -> controls.resetLayout() }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showResizeDialog(controlId: String, currentScale: Float) {
        showSeekDialog(
            "${controlLabel(controlId)} size",
            60..175,
            (currentScale * 100f).roundToInt().coerceIn(60, 175),
        ) { value ->
            controls.setSizeScale(controlId, value / 100f)
        }
    }

    private fun controlLabel(controlId: String): String = when (controlId) {
        TouchControlsView.ID_MOVE -> "Move stick"
        TouchControlsView.ID_C -> "Camera stick"
        TouchControlsView.ID_DPAD_GROUP -> "D-Pad"
        else -> "Control $controlId"
    }

    // ------------------------------------------------------------------ controller mapping

    private val gameButtons = listOf(
        SunPadButtons.A, SunPadButtons.B, SunPadButtons.X,
        SunPadButtons.Y, SunPadButtons.Z,
    )

    private fun gameButtonName(gameBit: Int): String = when (gameBit) {
        SunPadButtons.A -> "GameCube A"
        SunPadButtons.B -> "GameCube B"
        SunPadButtons.X -> "GameCube X"
        SunPadButtons.Y -> "GameCube Y"
        SunPadButtons.Z -> "GameCube Z"
        else -> "Unknown"
    }

    private fun connectedControllerName(): String? {
        for (id in InputDevice.getDeviceIds()) {
            val device = InputDevice.getDevice(id) ?: continue
            if ((device.sources and InputDevice.SOURCE_GAMEPAD) != 0)
                return device.name
        }
        return null
    }

    private fun showMappingDialog() {
        val mapping = ControllerMapping.load(this)
        val controllerName = connectedControllerName()
        val message = if (controllerName != null)
            "Connected: $controllerName\nOnly A, B, X, Y, and Z are remapped. " +
            "Analog triggers, sticks, D-pad, Start, and L stay unchanged."
        else
            "No gamepad is connected. You can review or reset the saved " +
            "mapping; connect a controller to test it."
        val items = ArrayList<String>()
        for (gameBit in gameButtons) {
            val physical = mapping.physicalFor(gameBit)
            items.add("${gameButtonName(gameBit)} — ${physical?.label ?: "?"}")
        }
        items.add("Reset to Default")
        items.add("Done")
        AlertDialog.Builder(this)
            .setTitle("Controller Button Mapping")
            .setMessage(message)
            .setItems(items.toTypedArray()) { _, which ->
                when {
                    which < gameButtons.size -> showPhysicalChoices(gameButtons[which])
                    which == gameButtons.size -> {
                        ControllerMapping.reset(this)
                        gamepad.reloadMapping()
                        Toast.makeText(this, "Controller mapping reset to default", Toast.LENGTH_SHORT).show()
                        showMappingDialog()
                    }
                    else -> { /* Done */ }
                }
            }
            .show()
    }

    private fun showPhysicalChoices(gameBit: Int) {
        AlertDialog.Builder(this)
            .setTitle(gameButtonName(gameBit))
            .setMessage("Choose the physical controller button. If it is already " +
                        "assigned, the two assignments swap.")
            .setItems(PhysicalButton.ALL.map { it.label }.toTypedArray()) { _, which ->
                val physical = PhysicalButton.ALL[which]
                val mapping = ControllerMapping.assign(
                    ControllerMapping.load(this), physical, gameBit)
                ControllerMapping.save(this, mapping)
                gamepad.reloadMapping()
                showMappingDialog()
            }
            .setNegativeButton("Cancel") { _, _ -> showMappingDialog() }
            .show()
    }

    // ------------------------------------------------------------------ helpers

    private fun setImmersive() {
        window.decorView.windowInsetsController?.let { controller ->
            controller.hide(WindowInsets.Type.systemBars())
            controller.systemBarsBehavior =
                WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } ?: run {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        or View.SYSTEM_UI_FLAG_FULLSCREEN
                        or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val REQUEST_IMAGE = 1
        private const val REQUEST_MODULE = 2
        private const val MENU_SCALE = 1
        private const val MENU_ASPECT = 2
        private const val MENU_OPACITY = 3
        private const val MENU_SIZE = 4
        private const val MENU_CSTICK = 5
        private const val MENU_EDIT_LAYOUT = 6
        private const val MENU_RESET_LAYOUT = 7
        private const val MENU_MAPPING = 8
        private const val MENU_HUD = 9
        private const val MENU_IMPORT = 10
        private const val MENU_QUIT = 11
    }
}

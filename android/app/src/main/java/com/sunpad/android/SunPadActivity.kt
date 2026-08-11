package com.sunpad.android

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
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
import android.widget.PopupMenu
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import com.sunpad.android.input.GamepadReader
import com.sunpad.android.input.TouchControlsView
import java.util.Locale

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
    private val gamepad = GamepadReader()

    private val merged = GameInputState()
    private val touchState = GameInputState()

    private var surfaceReady = false
    private var started = false
    private var hudVisible = false
    private var lastHudUpdate = 0L
    private val uiHandler = Handler(Looper.getMainLooper())

    private val prefs by lazy { getSharedPreferences("sunpad", MODE_PRIVATE) }

    // ------------------------------------------------------------------ lifecycle

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        importer = GameDataImporter(this)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setImmersive()

        rootView = FrameLayout(this)
        surfaceView = SurfaceView(this)
        surfaceView.holder.addCallback(this)
        rootView.addView(surfaceView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        controls = TouchControlsView(this)
        controls.listener = object : TouchControlsView.Listener {
            override fun onMenuTap() = showMenu()
        }
        rootView.addView(controls, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))

        hud = TextView(this).apply {
            textColor = Color.WHITE
            textSize = 13f
            setShadowLayer(3f, 1f, 1f, Color.BLACK)
            visibility = View.GONE
        }
        rootView.addView(hud, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.START).apply { topMargin = dp(24); leftMargin = dp(8) })

        setContentView(rootView)
        gamepad.attach(rootView)

        applyPrefsToControls()
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    override fun onResume() {
        super.onResume()
        setImmersive()
        SunPadNative.nativeResume()
    }

    override fun onPause() {
        SunPadNative.nativePause()
        super.onPause()
    }

    override fun onDestroy() {
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        gamepad.detach(rootView)
        SunPadNative.nativeStop()
        super.onDestroy()
    }

    // ------------------------------------------------------------------ surface

    override fun surfaceCreated(holder: SurfaceHolder) {
        surfaceReady = true
        SunPadNative.nativeSetSurface(holder.surface)
        if (!started) {
            startGameIfReady()
        } else {
            // Surface recreated (rotation / resume): the swapchain is rebuilt
            // through the presenter, so unpause the runtime.
            SunPadNative.nativeResume()
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {
        SunPadNative.nativeSetSurface(holder.surface)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        surfaceReady = false
        SunPadNative.nativeSetSurface(null)
        SunPadNative.nativePause()
        controls.releaseAll()
    }

    // ------------------------------------------------------------------ game start

    private fun startGameIfReady() {
        if (started || !surfaceReady) return
        if (!importer.hasActiveGame() || !importer.hasModule()) {
            showSetupDialog()
            return
        }
        started = true
        Thread {
            val error = SunPadNative.nativeStart(
                importer.gameRoot.absolutePath,
                importer.discImagePath,
                importer.modulePath,
                importer.userDirectoryPath,
            )
            if (error != null) {
                started = false
                uiHandler.post {
                    Toast.makeText(this, "Start failed: $error", Toast.LENGTH_LONG).show()
                    showSetupDialog()
                }
            }
        }.start()
    }

    private fun showSetupDialog() {
        if (isFinishing || isDestroyed) return
        val items = ArrayList<String>()
        val actions = ArrayList<() -> Unit>()
        if (!importer.hasActiveGame()) {
            items.add("Import game data (GMSE01 ISO/GCM)…")
            actions.add { pickImage() }
        }
        if (!importer.hasModule()) {
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
        AlertDialog.Builder(this)
            .setTitle(if (started) "SunPad" else "SunPad — game data required")
            .setMessage(
                if (started) ""
                else "SunPad never bundles or downloads game data. Import your " +
                     "own Super Mario Sunshine USA (GMSE01) disc image and a " +
                     "locally generated game module to start.")
            .setItems(items.toTypedArray()) { _, which -> actions[which]() }
            .setOnCancelListener { if (!started) finish() }
            .show()
    }

    private fun pickImage() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/octet-stream", "*/*"))
        }
        startActivityForResult(intent, REQUEST_IMAGE)
    }

    private fun pickModule() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        startActivityForResult(intent, REQUEST_MODULE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK || data?.data == null) {
            showSetupDialog()
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
                }
                startGameIfReady()
            }
        }.start()
    }

    private fun importModule(uri: android.net.Uri) {
        Thread {
            val error = importer.importModule(uri)
            uiHandler.post {
                if (error != null) {
                    Toast.makeText(this, error, Toast.LENGTH_LONG).show()
                } else {
                    Toast.makeText(this, "Module installed.", Toast.LENGTH_SHORT).show()
                }
                startGameIfReady()
            }
        }.start()
    }

    // ------------------------------------------------------------------ menu

    private fun showMenu() {
        if (isFinishing) return
        val menu = PopupMenu(this, controls)
        menu.menu.add(0, MENU_SCALE, 0, "Render scale: ${prefs.getInt("scale", 1)}×")
        menu.menu.add(0, MENU_ASPECT, 1, "Aspect ratio")
        menu.menu.add(0, MENU_OPACITY, 2, "Control opacity…")
        menu.menu.add(0, MENU_SIZE, 3, "Control size…")
        menu.menu.add(0, MENU_CSTICK, 4, "Modern C-stick (flip horizontal)")
        menu.menu.add(0, MENU_HUD, 5, if (hudVisible) "Hide diagnostics" else "Show diagnostics")
        menu.menu.add(0, MENU_IMPORT, 6, "Import game data…")
        menu.menu.add(0, MENU_QUIT, 7, "Quit")
        val cStickItem = menu.menu.getItem(4)
        cStickItem.isCheckable = true
        cStickItem.isChecked = prefs.getBoolean("modernCStick", false)
        menu.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                MENU_SCALE -> cycleRenderScale()
                MENU_ASPECT -> pickAspect()
                MENU_OPACITY -> showSeekDialog("Control opacity", 25..90, prefs.getInt("opacity", 55)) {
                    controls.opacity = it / 100f
                    prefs.edit().putInt("opacity", it).apply()
                }
                MENU_SIZE -> showSeekDialog("Control size", 60..140, prefs.getInt("size", 100)) {
                    controls.scale = it / 100f
                    prefs.edit().putInt("size", it).apply()
                }
                MENU_CSTICK -> {
                    val on = !item.isChecked
                    item.isChecked = on
                    prefs.edit().putBoolean("modernCStick", on).apply()
                    SunPadNative.nativeSetModernCStick(on)
                }
                MENU_HUD -> toggleHud()
                MENU_IMPORT -> showSetupDialog()
                MENU_QUIT -> finish()
            }
            true
        }
        menu.show()
    }

    private fun cycleRenderScale() {
        val next = (prefs.getInt("scale", 1) % 4) + 1
        prefs.edit().putInt("scale", next).apply()
        SunPadNative.nativeSetRenderScale(next)
    }

    private fun pickAspect() {
        val modes = arrayOf("Original 4:3", "Widescreen 16:9", "Fill screen")
        val current = prefs.getInt("aspect", 0)
        AlertDialog.Builder(this)
            .setTitle("Aspect ratio")
            .setSingleChoiceItems(modes, current) { _, which ->
                prefs.edit().putInt("aspect", which).apply()
                SunPadNative.nativeSetAspectRatioMode(which)
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
        AlertDialog.Builder(this)
            .setTitle(title)
            .setView(slider, pad, pad / 2, pad, 0)
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
        SunPadNative.nativeSetModernCStick(prefs.getBoolean("modernCStick", false))
        SunPadNative.nativeSetRenderScale(prefs.getInt("scale", 1))
        SunPadNative.nativeSetAspectRatioMode(prefs.getInt("aspect", 0))
    }

    // ------------------------------------------------------------------ input loop

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (isFinishing || isDestroyed) return
            publishInput()
            if (hudVisible && frameTimeNanos - lastHudUpdate > 500_000_000L) {
                lastHudUpdate = frameTimeNanos
                hud.text = String.format(
                    Locale.US, "%.1f FPS  %.2f×  %s",
                    SunPadNative.nativeCurrentFPS(),
                    SunPadNative.nativeCurrentSpeed(),
                    SunPadNative.nativeEfbResolution())
            }
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    private fun publishInput() {
        merged.reset()
        controls.snapshot(touchState)
        merged.copyFrom(touchState)
        gamepad.merge(merged)
        SunPadNative.nativePublishInput(merged)
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
        private const val MENU_HUD = 6
        private const val MENU_IMPORT = 7
        private const val MENU_QUIT = 8
    }
}

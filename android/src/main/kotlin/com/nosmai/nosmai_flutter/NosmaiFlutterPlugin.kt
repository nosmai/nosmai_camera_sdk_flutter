package com.nosmai.nosmai_flutter
import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.util.Base64
import android.util.Log
import android.view.Surface
import android.view.ViewGroup
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import android.os.Handler
import android.os.Looper
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import android.content.ContentValues
import android.provider.MediaStore
import android.os.Build
import android.os.Environment
import java.io.IOException

// Nosmai Android SDK imports (from bundled AAR)
import com.nosmai.effect.api.NosmaiSDK
import com.nosmai.effect.api.NosmaiBeauty
import com.nosmai.effect.NosmaiEffects
import com.nosmai.effect.api.NosmaiPreviewView
import com.nosmai.effect.api.NosmaiCloud

class NosmaiFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var textures: TextureRegistry
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingLicenseKey: String? = null
    private var isSdkInitialized = false

    // Texture/surface
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var pendingSurfaceWidth: Int? = null
    private var pendingSurfaceHeight: Int? = null

    // Hidden preview (ensures GL context prepared for some engines)
    private var previewView: NosmaiPreviewView? = null
    // Camera2 helper removed; rely on SDK internal camera pipeline
    // private var camera2Helper: Camera2Helper? = null
    private val REQ_CAMERA = 2001
    private var surfaceReboundOnce = false
    private var fpsCount = 0
    private var fpsLastMs = 0L

    companion object {
        private const val TAG = "NosmaiFlutterPlugin"
        private const val CHANNEL = "nosmai_camera_sdk"
        private const val ASSET_MANIFEST_PATH = "flutter_assets/AssetManifest.json"
        private const val FILTERS_PREFIX = "assets/filters/"
        private const val CACHE_DIR_NAME = "NosmaiLocalFilters"
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        textures = flutterPluginBinding.textureRegistry
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // Release texture & surface
        try { surface?.release() } catch (_: Throwable) {}
        try { textureEntry?.release() } catch (_: Throwable) {}
        surface = null
        textureEntry = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android")
            "getLocalFilters" -> handleGetLocalFilters(result)
            "applyEffect" -> handleApplyEffect(call, result)
            "initWithLicense" -> handleInitWithLicense(call, result)
            "createTexture", "createPreviewTexture" -> handleCreateTexture(result)
            "setRenderSurface" -> handleSetRenderSurface(call, result)
            "clearRenderSurface" -> handleClearRenderSurface(result)
            "configureCamera" -> handleConfigureCamera(call, result)
            "startProcessing" -> handleStartProcessing(result)
            "stopProcessing" -> handleStopProcessing(result)
            "switchCamera" -> handleSwitchCamera(result)
            "detachCameraView" -> result.success(null)
            "removeAllFilters" -> handleRemoveAllFilters(result)
            "startRecording" -> handleStartRecording(result)
            "stopRecording" -> handleStopRecording(result)
            "isRecording" -> result.success(isRecording)
            "getCurrentRecordingDuration" -> result.success(getCurrentRecordingDurationSeconds())
            // Beauty / Color built-ins
            "applySkinSmoothing" -> handleApplySkinSmoothing(call, result)
            "applySkinWhitening" -> handleApplySkinWhitening(call, result)
            "applyFaceSlimming" -> handleApplyFaceSlimming(call, result)
            "applyEyeEnlargement" -> handleApplyEyeEnlargement(call, result)
            "applyNoseSize" -> handleApplyNoseSize(call, result)
            "applyBrightnessFilter" -> handleApplyBrightness(call, result)
            "applyContrastFilter" -> handleApplyContrast(call, result)
            "applyHue" -> handleApplyHue(call, result)
            "removeBuiltInFilters" -> handleRemoveBuiltInBeautyFilters(result)
            // Cloud filters
            "isCloudFilterEnabled" -> handleIsCloudFilterEnabled(result)
            "getCloudFilters" -> handleGetCloudFilters(result)
            "downloadCloudFilter" -> handleDownloadCloudFilter(call, result)
            "getFilters" -> handleGetFilters(result)
            // Photo capture and gallery functions
            "capturePhoto" -> handleCapturePhoto(result)
            "saveImageToGallery" -> handleSaveImageToGallery(call, result)
            "saveVideoToGallery" -> handleSaveVideoToGallery(call, result)
            // SDK cleanup and management
            "cleanup" -> handleCleanup(result)
            "clearFilterCache" -> handleClearFilterCache(result)
            "reinitializePreview" -> handleReinitializePreview(result)
            else -> result.notImplemented()
        }
    }

    // --- Local Filters ---
    private fun handleGetLocalFilters(result: Result) {
        try {
            val manifestJson = readAssetText(ASSET_MANIFEST_PATH)
            if (manifestJson == null) {
                result.success(emptyList<Any>())
                return
            }

            val manifest = JSONObject(manifestJson)
            val keys = manifest.keys()
            val out = ArrayList<Map<String, Any?>>()

            while (keys.hasNext()) {
                val assetPath = keys.next()
                if (!assetPath.startsWith(FILTERS_PREFIX) || !assetPath.endsWith(".nosmai")) continue

                val name = File(assetPath).nameWithoutExtension
                val displayName = toTitleCase(name)

                // Copy asset to a real file path under cache (once)
                val cachedFile = ensureAssetCached(assetPath)
                val fileSize = if (cachedFile != null && cachedFile.exists()) cachedFile.length().toInt() else 0

                // Extract filterType/display/description from .nosmai manifest via SDK internal native
                val (ftype, disp, desc, hasPreview) = extractManifestFieldsFromNosmai(name)

                val map = HashMap<String, Any?>()
                map["id"] = name
                map["name"] = name
                map["displayName"] = if (!disp.isNullOrBlank()) disp else displayName
                map["description"] = desc ?: ""
                map["path"] = cachedFile?.absolutePath ?: ""
                map["fileSize"] = fileSize
                map["type"] = "local"
                if (ftype == "filter" || ftype == "effect") map["filterType"] = ftype
                map["isDownloaded"] = true
                map["isFree"] = true

                // Optional preview via embedded preview extractor
                val previewB64 = tryExtractPreviewBase64(name)
                if (!previewB64.isNullOrBlank()) {
                    map["previewImageBase64"] = previewB64
                    // Also set previewUrl for consistency with iOS
                    map["previewUrl"] = "data:image/jpeg;base64,$previewB64"
                }

                out.add(map)
            }

            result.success(out)
        } catch (t: Throwable) {
            Log.e(TAG, "getLocalFilters error", t)
            result.error("FILTER_LOAD_ERROR", t.message, null)
        }
    }

    // Remove previous scanLocalFiltersFromEngine attempts; we now directly use NosmaiFilterManager

    // Removed engine type map helper as we now rely on NosmaiFilterManager grouping

    // --- Apply Effect (.nosmai) ---
    private fun handleApplyEffect(call: MethodCall, result: Result) {
        val effectPathArg = call.argument<String>("effectPath")
        if (effectPathArg.isNullOrBlank()) {
            result.success(false)
            return
        }

        try {
            // Resolve: if it's not an absolute existing file, treat as asset or name
            val file = resolveEffectToFile(effectPathArg)
            if (file == null || !file.exists()) {
                Log.w(TAG, "Effect file not found for: $effectPathArg")
                result.success(false)
                return
            }

            // Prefer direct SDK path-based application
            NosmaiEffects.applyEffect(file.absolutePath)
            result.success(true)
        } catch (t: Throwable) {
            Log.e(TAG, "applyEffect error", t)
            result.success(false)
        }
    }

    // --- Initialization ---
    private fun handleInitWithLicense(call: MethodCall, result: Result) {
        try {
            val key = call.argument<String>("licenseKey").orEmpty()
            val act = activity
            if (act == null) {
                pendingLicenseKey = key
                result.success(true)
                return
            }
            initializeSdk(act, key)
            result.success(true)
        } catch (t: Throwable) {
            Log.e(TAG, "initWithLicense error", t)
            result.success(false)
        }
    }

    private fun initializeSdk(act: Activity, key: String) {
        if (isSdkInitialized) return
        NosmaiSDK.initialize(act, key)
        // Prepare a tiny hidden preview view to ensure GL context is created on some devices
        if (previewView == null) previewView = NosmaiPreviewView(act)
        val root = act.findViewById<ViewGroup>(android.R.id.content)
        if (previewView?.parent == null) {
            val lp = ViewGroup.LayoutParams(1, 1)
            root.addView(previewView, lp)
            previewView?.alpha = 0f
        }
        // Default mirror (front camera UX)
        try { NosmaiSDK.setMirrorX(true) } catch (_: Throwable) {}
        isSdkInitialized = true
        // Bind any pending surface
        try {
            val w = pendingSurfaceWidth
            val h = pendingSurfaceHeight
            if (surface != null && w != null && h != null) {
                NosmaiSDK.setRenderSurface(surface!!, w, h)
                NosmaiSDK.setMirrorX(true)
                pendingSurfaceWidth = null
                pendingSurfaceHeight = null
            }
        } catch (_: Throwable) {}
    }

    // --- Texture/Surface helpers ---
    private fun handleCreateTexture(result: Result) {
        try {
            // Release any existing texture first
            val oldEntry = textureEntry
            if (oldEntry != null) {
                textureEntry = null
                oldEntry.release()
            }
            
            // Create new texture
            textureEntry = textures.createSurfaceTexture()
            surfaceReboundOnce = false // Reset binding flag for new texture
            result.success(textureEntry!!.id().toInt())
        } catch (t: Throwable) {
            Log.e(TAG, "createTexture error", t)
            result.error("TEXTURE_ERROR", t.message, null)
        }
    }

    private fun handleSetRenderSurface(call: MethodCall, result: Result) {
        try {
            val texId = call.argument<Number>("textureId")?.toInt()
            val w = call.argument<Number>("width")?.toInt() ?: 720
            val h = call.argument<Number>("height")?.toInt() ?: 1280
            if (texId == null) {
                result.error("ARG_ERROR", "textureId required", null)
                return
            }
            val entry = textureEntry
            if (entry == null) {
                result.success(false)
                return
            }
            val st = entry.surfaceTexture()
            st.setDefaultBufferSize(w, h)
            surface = Surface(st)
            
            if (isSdkInitialized) {
                NosmaiSDK.setRenderSurface(surface!!, w, h)
                try { NosmaiSDK.setMirrorX(true) } catch (_: Throwable) {}
                result.success(true)
            } else {
                // Defer until init
                pendingSurfaceWidth = w
                pendingSurfaceHeight = h
                result.success(true)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "setRenderSurface error", t)
            result.success(false)
        }
    }

    // --- Camera / Processing ---
    private var isFrontCamera: Boolean = true
    private var isSwitchingCamera: Boolean = false
    private var lastSwitchAtMs: Long = 0L
    private var isProcessingActive: Boolean = false

    private fun handleConfigureCamera(call: MethodCall, result: Result) {
        try {
            val pos = call.argument<String>("position") ?: "front"
            isFrontCamera = (pos == "front")
            try { NosmaiSDK.setCameraFacing(isFrontCamera) } catch (_: Throwable) {}
            try { NosmaiSDK.setMirrorX(isFrontCamera) } catch (_: Throwable) {}
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "configureCamera error", t)
            result.error("CONFIG_ERROR", t.message, null)
        }
    }

    private fun handleStartProcessing(result: Result) {
        try {
            // Ensure preview view exists
            val act = activity
            if (act != null && previewView == null) {
                previewView = NosmaiPreviewView(act)
                val root = act.findViewById<ViewGroup>(android.R.id.content)
                if (previewView?.parent == null) {
                    val lp = ViewGroup.LayoutParams(1, 1)
                    root.addView(previewView, lp)
                    previewView?.alpha = 0f
                }
            }
            if (previewView != null) {
                NosmaiSDK.startProcessing(previewView!!)
                isProcessingActive = true
                try { NosmaiSDK.setCameraFacing(isFrontCamera) } catch (_: Throwable) {}
                try { NosmaiSDK.setMirrorX(isFrontCamera) } catch (_: Throwable) {}
                result.success(null)
            } else {
                result.error("NO_PREVIEW", "Preview not initialized", null)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "startProcessing error", t)
            result.error("START_ERROR", t.message, null)
        }
    }

    private fun handleStopProcessing(result: Result) {
        try {
            NosmaiSDK.stopProcessing()
            isProcessingActive = false
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "stopProcessing error", t)
            result.error("STOP_ERROR", t.message, null)
        }
    }

    private fun handleSwitchCamera(result: Result) {
        try {
            val now = System.currentTimeMillis()
            if (isSwitchingCamera || (now - lastSwitchAtMs) < 700) {
                result.success(false)
                return
            }
            isSwitchingCamera = true
            lastSwitchAtMs = now

            val act = activity
            if (act == null) {
                isSwitchingCamera = false
                result.error("NO_ACTIVITY", "Activity not available", null)
                return
            }

            act.runOnUiThread {
                try {
                    // Toggle target facing
                    isFrontCamera = !isFrontCamera

                    // Reset surface bind flag so SDK can adjust if needed
                    surfaceReboundOnce = false

                    // Apply facing to SDK; rely on SDK internal camera control
                    try { NosmaiSDK.setCameraFacing(isFrontCamera) } catch (_: Throwable) {}
                    try { NosmaiSDK.setMirrorX(isFrontCamera) } catch (_: Throwable) {}

                    result.success(true)
                    isSwitchingCamera = false
                } catch (t: Throwable) {
                    Log.e(TAG, "switchCamera error", t)
                    result.success(false)
                    isSwitchingCamera = false
                }
            }
        } catch (t: Throwable) {
            isSwitchingCamera = false
            Log.e(TAG, "switchCamera error", t)
            result.success(false)
        }
    }

    private fun handleRemoveAllFilters(result: Result) {
        try {
            // Remove any applied .nosmai effect (single active effect model)
            NosmaiEffects.removeEffect()
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "removeAllFilters error", t)
            result.error("REMOVE_FILTERS_ERROR", t.message, null)
        }
    }

    // --- Recording ---
    private var isRecording: Boolean = false
    private var recordingStartMs: Long = 0L
    private var recordingPath: String? = null

    private fun handleStartRecording(result: Result) {
        try {
            val pv = previewView
            if (pv == null) {
                result.success(false)
                return
            }
            // Prepare output file in app cache (Flutter can save to gallery later)
            val outDir = File(context.cacheDir, "NosmaiRecordings")
            if (!outDir.exists()) outDir.mkdirs()
            val timestamp = java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US).format(java.util.Date())
            val file = File(outDir, "nosmai_$timestamp.mp4")

            NosmaiSDK.startRecording(pv, file.absolutePath, object : com.nosmai.effect.api.NosmaiSDK.RecordingCallback {
                override fun onStarted(success: Boolean, error: String?) {
                    if (success) {
                        isRecording = true
                        recordingStartMs = System.currentTimeMillis()
                        recordingPath = file.absolutePath
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
            })
        } catch (t: Throwable) {
            Log.e(TAG, "startRecording error", t)
            result.success(false)
        }
    }

    private fun handleStopRecording(result: Result) {
        try {
            if (!isRecording) {
                result.success(mapOf(
                    "success" to false,
                    "duration" to 0.0,
                    "fileSize" to 0,
                    "error" to "Not currently recording"
                ))
                return
            }
            val start = recordingStartMs
            val pathAtStop = recordingPath
            com.nosmai.effect.api.NosmaiSDK.stopRecording(object : com.nosmai.effect.api.NosmaiSDK.RecordingCallback {
                override fun onCompleted(outputPath: String?, success: Boolean, error: String?) {
                    isRecording = false
                    val finalPath = outputPath ?: pathAtStop
                    val durationSec = if (start > 0) ((System.currentTimeMillis() - start) / 1000.0) else 0.0
                    val size = try { if (finalPath != null) File(finalPath).length().toInt() else 0 } catch (_: Throwable) { 0 }
                    val map = mutableMapOf<String, Any?>(
                        "success" to success,
                        "duration" to durationSec,
                        "fileSize" to size
                    )
                    if (finalPath != null) map["videoPath"] = finalPath
                    if (!success && !error.isNullOrBlank()) map["error"] = error
                    result.success(map)
                }
            })
        } catch (t: Throwable) {
            Log.e(TAG, "stopRecording error", t)
            isRecording = false
            result.success(mapOf(
                "success" to false,
                "duration" to 0.0,
                "fileSize" to 0,
                "error" to (t.message ?: "Unknown error")
            ))
        }
    }

    private fun getCurrentRecordingDurationSeconds(): Double {
        return if (isRecording && recordingStartMs > 0) {
            (System.currentTimeMillis() - recordingStartMs) / 1000.0
        } else 0.0
    }

    // --- Beauty / Color built-ins (Android NosmaiBeauty mapping) ---
    private fun handleApplySkinSmoothing(call: MethodCall, result: Result) {
        try {
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            // iOS uses ~0..10, Android expects 0..1
            val normalized = (level / 10.0).coerceIn(0.0, 1.0)
            NosmaiBeauty.applySkinSmoothing(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplySkinWhitening(call: MethodCall, result: Result) {
        try {
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            val normalized = (level / 10.0).coerceIn(0.0, 1.0)
            NosmaiBeauty.applySkinWhitening(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyFaceSlimming(call: MethodCall, result: Result) {
        try {
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            val normalized = (level / 10.0).coerceIn(0.0, 1.0)
            NosmaiBeauty.applyFaceSlimming(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyEyeEnlargement(call: MethodCall, result: Result) {
        try {
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            val normalized = (level / 10.0).coerceIn(0.0, 1.0)
            NosmaiBeauty.applyEyeEnlargement(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyNoseSize(call: MethodCall, result: Result) {
        try {
            val level = call.argument<Number>("level")?.toDouble() ?: 0.0
            val normalized = (level / 100.0).coerceIn(0.0, 1.0)
            NosmaiBeauty.applyNoseSize(normalized.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyBrightness(call: MethodCall, result: Result) {
        try {
            val brightness = call.argument<Number>("brightness")?.toDouble() ?: 0.0
            // iOS uses -1.0..+1.0; clamp for Android
            val clamped = brightness.coerceIn(-1.0, 1.0)
            NosmaiBeauty.applyBrightness(clamped.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyContrast(call: MethodCall, result: Result) {
        try {
            val contrast = call.argument<Number>("contrast")?.toDouble() ?: 1.0
            // iOS uses 0.0..2.0 typical; clamp for parity
            val clamped = contrast.coerceIn(0.0, 2.0)
            NosmaiBeauty.applyContrast(clamped.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleApplyHue(call: MethodCall, result: Result) {
        try {
            val hue = call.argument<Number>("hueAngle")?.toDouble() ?: 0.0
            NosmaiBeauty.applyHue(hue.toFloat())
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    private fun handleRemoveBuiltInBeautyFilters(result: Result) {
        try {
            NosmaiBeauty.removeAllBeautyFilters()
            result.success(null)
        } catch (t: Throwable) { result.error("FILTER_ERROR", t.message, null) }
    }

    // --- Cloud Filters ---
    private fun handleIsCloudFilterEnabled(result: Result) {
        try {
            result.success(NosmaiCloud.isEnabled())
        } catch (t: Throwable) { result.success(false) }
    }

    private fun mapCategoryToFilterType(cat: String?): String {
        val c = (cat ?: "").lowercase()
        return when (c) {
            "fx-and-filters", "filter" -> "filter"
            "special-effects", "beauty-effects", "effect" -> "effect"
            else -> "effect"
        }
    }

    private fun handleGetCloudFilters(result: Result) {
        try {
            val list = NosmaiCloud.list()
            val out = ArrayList<Map<String, Any?>>()
            for (it in list) {
                val id = it.id
                val name = it.name
                val displayName = toTitleCase(if (name.isNotBlank()) name else id)
                val type = "cloud"
                val downloaded = it.isDownloaded
                val localPath = it.localPath
                val filterType = mapCategoryToFilterType(it.category)
                val fileSize = try { if (downloaded && localPath.isNotBlank()) File(localPath).length().toInt() else 0 } catch (_: Throwable) { 0 }

                val m = HashMap<String, Any?>()
                m["id"] = id
                m["name"] = name
                m["displayName"] = displayName
                m["type"] = type
                m["filterType"] = filterType
                m["isDownloaded"] = downloaded
                m["fileSize"] = fileSize
                m["isFree"] = true
                
                // Include path for downloaded filters
                if (downloaded && localPath.isNotBlank()) {
                    m["path"] = localPath
                    m["localPath"] = localPath
                    // Try preview extract for downloaded
                    try {
                        val bmp = com.nosmai.effect.NosmaiFilterManager.loadPreviewImageForFilter(localPath)
                        if (bmp != null) {
                            m["previewImageBase64"] = bitmapToBase64(bmp)
                        }
                    } catch (_: Throwable) {}
                }
                
                // ALWAYS include thumbnailUrl/previewUrl if available
                if (it.thumbnailUrl.isNotBlank()) {
                    m["previewUrl"] = it.thumbnailUrl  // Use previewUrl 
                    m["thumbnailUrl"] = it.thumbnailUrl  // Also include thumbnailUrl for compatibility
                }
                
                out.add(m)
            }
            result.success(out)
        } catch (t: Throwable) {
            result.error("CLOUD_FILTERS_ERROR", t.message, null)
        }
    }

    private fun handleDownloadCloudFilter(call: MethodCall, result: Result) {
        val filterId = call.argument<String>("filterId")
        if (filterId.isNullOrBlank()) { result.error("ARG_ERROR", "filterId required", null); return }
        try {
            val latch = java.util.concurrent.CountDownLatch(1)
            var ok = false
            var path: String? = null
            var err: String? = null
            NosmaiCloud.download(filterId, object : NosmaiCloud.DownloadCallback {
                override fun onComplete(id: String, success: Boolean, localPath: String?, error: String?) {
                    ok = success
                    path = localPath
                    err = error
                    latch.countDown()
                }
            })
            latch.await()
            val map = HashMap<String, Any?>()
            map["success"] = ok
            if (ok && !path.isNullOrBlank()) map["path"] = path
            if (!ok && !err.isNullOrBlank()) map["error"] = err
            result.success(map)
        } catch (t: Throwable) {
            result.success(mapOf("success" to false, "error" to (t.message ?: "Unknown error")))
        }
    }

    private fun handleGetFilters(result: Result) {
        try {
            val grouped = com.nosmai.effect.NosmaiEffects.getFilters()
            val out = ArrayList<Map<String, Any?>>()
            if (grouped != null) {
                for (entry in grouped.entries) {
                    val list = entry.value as? List<*> ?: continue
                    for (item in list) {
                        val m = item as? Map<*, *> ?: continue
                        val name = (m["name"] as? String)?.trim().orEmpty()
                        if (name.isBlank()) continue
                        val id = ((m["filterId"] as? String)?.takeIf { it.isNotBlank() } ?: name)
                        val displayName = ((m["displayName"] as? String)?.takeIf { it.isNotBlank() } ?: toTitleCase(name))
                        val type = (m["type"] as? String)?.lowercase() ?: "local"
                        val path = ((m["localPath"] as? String)?.takeIf { it.isNotBlank() } ?: (m["path"] as? String)).orEmpty()
                        val fileSize = (m["fileSize"] as? Number)?.toInt() ?: 0
                        val filterType = (m["filterType"] as? String)?.lowercase() ?: mapCategoryToFilterType(m["category"] as? String)
                        val downloaded = (m["isDownloaded"] as? Boolean) ?: (type == "local")
                        val previewB64 = m["previewBase64"] as? String
                        val thumbUrl = m["thumbnailUrl"] as? String

                        val outMap = HashMap<String, Any?>()
                        outMap["id"] = id
                        outMap["name"] = name
                        outMap["displayName"] = displayName
                        outMap["type"] = type
                        outMap["filterType"] = filterType
                        outMap["isDownloaded"] = downloaded
                        outMap["fileSize"] = fileSize
                        if (path.isNotBlank()) outMap["path"] = path
                        
                        // Include preview data if available
                        if (!previewB64.isNullOrBlank()) outMap["previewImageBase64"] = previewB64
                        
                        // ALWAYS include thumbnailUrl/previewUrl if available (matching iOS behavior)
                        if (!thumbUrl.isNullOrBlank()) {
                            outMap["previewUrl"] = thumbUrl  // Use previewUrl to match iOS field name
                            outMap["thumbnailUrl"] = thumbUrl  // Also include thumbnailUrl for compatibility
                        }
                        
                        out.add(outMap)
                    }
                }
            }
            result.success(out)
        } catch (t: Throwable) { result.error("GET_FILTERS_ERROR", t.message, null) }
    }

    private fun handleClearRenderSurface(result: Result) {
        try {
            // Clear SDK render surface
            try { NosmaiSDK.clearRenderSurface() } catch (_: Throwable) {}
            
            // Release surface and texture
            surface?.release()
            surface = null
            
            // Properly release texture entry
            val entry = textureEntry
            textureEntry = null
            entry?.release()
            
            // Reset surface binding flag
            surfaceReboundOnce = false
            
            result.success(true)
        } catch (t: Throwable) {
            Log.e(TAG, "clearRenderSurface error", t)
            result.success(false)
        }
    }

    // --- Photo Capture and Gallery Functions ---
    private fun handleCapturePhoto(result: Result) {
        try {
            // We need to capture from the rendered surface
            val surf = surface
            val entry = textureEntry
            
            if (surf == null || entry == null) {
                result.success(mapOf(
                    "success" to false,
                    "error" to "Surface not initialized for capture"
                ))
                return
            }

            // Get dimensions
            val width = pendingSurfaceWidth ?: 720
            val height = pendingSurfaceHeight ?: 1280
            
            // Method 1: Try to read pixels from the current rendered frame
            Handler(Looper.getMainLooper()).post {
                try {
                    // Create bitmap to hold the captured image
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    
                    // Try to capture using TextureView approach
                    val textureView = android.view.TextureView(context)
                    val surfaceTexture = entry.surfaceTexture()
                    textureView.setSurfaceTexture(surfaceTexture)
                    
                    // Get the bitmap from TextureView
                    val captureBitmap = textureView.getBitmap(bitmap)
                    
                    if (captureBitmap != null) {
                        // Process the captured bitmap in background
                        Thread {
                            try {
                                val baos = ByteArrayOutputStream()
                                captureBitmap.compress(Bitmap.CompressFormat.JPEG, 80, baos)
                                val imageData = baos.toByteArray()
                                
                                val resultMap = HashMap<String, Any?>()
                                resultMap["success"] = true
                                resultMap["width"] = captureBitmap.width
                                resultMap["height"] = captureBitmap.height
                                resultMap["imageData"] = imageData
                                
                                Handler(Looper.getMainLooper()).post {
                                    result.success(resultMap)
                                }
                            } catch (e: Throwable) {
                                Handler(Looper.getMainLooper()).post {
                                    result.success(mapOf(
                                        "success" to false,
                                        "error" to "Failed to process image: ${e.message}"
                                    ))
                                }
                            }
                        }.start()
                    } else {
                        // Fallback: capture using OpenGL readPixels approach
                        captureUsingOpenGL(width, height, result)
                    }
                } catch (e: Throwable) {
                    Log.e(TAG, "Error capturing photo", e)
                    // Try fallback method
                    captureUsingOpenGL(width, height, result)
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "capturePhoto error", t)
            result.success(mapOf(
                "success" to false,
                "error" to "Failed to capture photo: ${t.message}"
            ))
        }
    }
    
    // Capture using OpenGL readPixels
    private fun captureUsingOpenGL(width: Int, height: Int, result: Result) {
        try {
            // This approach reads pixels directly from the OpenGL framebuffer
            val buffer = java.nio.ByteBuffer.allocateDirect(width * height * 4)
            buffer.order(java.nio.ByteOrder.nativeOrder())
            
            // Read pixels from the current OpenGL context
            android.opengl.GLES20.glReadPixels(0, 0, width, height, 
                android.opengl.GLES20.GL_RGBA, 
                android.opengl.GLES20.GL_UNSIGNED_BYTE, 
                buffer)
            
            buffer.rewind()
            
            // Convert buffer to bitmap
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.copyPixelsFromBuffer(buffer)
            
            // Flip bitmap vertically (OpenGL coordinates are upside down)
            val matrix = android.graphics.Matrix()
            matrix.postScale(1f, -1f, width / 2f, height / 2f)
            val flippedBitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height, matrix, true)
            
            // Process in background
            Thread {
                try {
                    val baos = ByteArrayOutputStream()
                    flippedBitmap.compress(Bitmap.CompressFormat.JPEG, 80, baos)
                    val imageData = baos.toByteArray()
                    
                    val resultMap = HashMap<String, Any?>()
                    resultMap["success"] = true
                    resultMap["width"] = flippedBitmap.width
                    resultMap["height"] = flippedBitmap.height
                    resultMap["imageData"] = imageData
                    
                    Handler(Looper.getMainLooper()).post {
                        result.success(resultMap)
                    }
                } catch (e: Throwable) {
                    Handler(Looper.getMainLooper()).post {
                        result.success(mapOf(
                            "success" to false,
                            "error" to "Failed to process captured image: ${e.message}"
                        ))
                    }
                }
            }.start()
        } catch (t: Throwable) {
            Log.e(TAG, "OpenGL capture error", t)
            result.success(mapOf(
                "success" to false,
                "error" to "Failed to capture using OpenGL: ${t.message}"
            ))
        }
    }

    private fun handleSaveImageToGallery(call: MethodCall, result: Result) {
        try {
            val imageData = call.argument<ByteArray>("imageData")
            val imageName = call.argument<String>("name") ?: "nosmai_photo_${System.currentTimeMillis()}"
            
            if (imageData == null) {
                result.error("INVALID_ARGUMENTS", "Image data is required", null)
                return
            }
            
            // Convert byte array to bitmap
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
            if (bitmap == null) {
                result.error("INVALID_IMAGE", "Could not create image from data", null)
                return
            }
            
            // Save to gallery based on Android version
            val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveImageToGalleryQ(bitmap, imageName)
            } else {
                saveImageToGalleryLegacy(bitmap, imageName)
            }
            
            if (saved) {
                result.success(mapOf(
                    "isSuccess" to true,
                    "message" to "Image saved to gallery"
                ))
            } else {
                result.error("SAVE_FAILED", "Failed to save image to gallery", null)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "saveImageToGallery error", t)
            result.error("SAVE_ERROR", "Error saving image: ${t.message}", null)
        }
    }

    private fun handleSaveVideoToGallery(call: MethodCall, result: Result) {
        try {
            val videoPath = call.argument<String>("videoPath")
            val videoName = call.argument<String>("name") ?: "nosmai_video_${System.currentTimeMillis()}"
            
            if (videoPath == null) {
                result.error("INVALID_ARGUMENTS", "Video path is required", null)
                return
            }
            
            val videoFile = File(videoPath)
            if (!videoFile.exists()) {
                result.error("FILE_NOT_FOUND", "Video file not found", null)
                return
            }
            
            // Save to gallery based on Android version
            val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveVideoToGalleryQ(videoFile, videoName)
            } else {
                saveVideoToGalleryLegacy(videoFile, videoName)
            }
            
            if (saved) {
                result.success(mapOf(
                    "isSuccess" to true,
                    "message" to "Video saved to gallery"
                ))
            } else {
                result.error("SAVE_FAILED", "Failed to save video to gallery", null)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "saveVideoToGallery error", t)
            result.error("SAVE_ERROR", "Error saving video: ${t.message}", null)
        }
    }

    // Helper methods for saving to gallery (Android Q+)
    private fun saveImageToGalleryQ(bitmap: Bitmap, imageName: String): Boolean {
        val resolver = context.contentResolver
        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "$imageName.jpg")
            put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Nosmai")
        }
        
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
        return if (uri != null) {
            try {
                resolver.openOutputStream(uri)?.use { outputStream ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream)
                }
                true
            } catch (e: IOException) {
                Log.e(TAG, "Failed to save image", e)
                false
            }
        } else {
            false
        }
    }
    
    private fun saveImageToGalleryLegacy(bitmap: Bitmap, imageName: String): Boolean {
        val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        val nosmaiDir = File(picturesDir, "Nosmai")
        if (!nosmaiDir.exists()) {
            nosmaiDir.mkdirs()
        }
        
        val imageFile = File(nosmaiDir, "$imageName.jpg")
        return try {
            FileOutputStream(imageFile).use { outputStream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream)
            }
            
            // Notify gallery about the new image
            val mediaScanIntent = android.content.Intent(android.content.Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            mediaScanIntent.data = android.net.Uri.fromFile(imageFile)
            context.sendBroadcast(mediaScanIntent)
            
            true
        } catch (e: IOException) {
            Log.e(TAG, "Failed to save image", e)
            false
        }
    }
    
    private fun saveVideoToGalleryQ(videoFile: File, videoName: String): Boolean {
        val resolver = context.contentResolver
        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "$videoName.mp4")
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Nosmai")
        }
        
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues)
        return if (uri != null) {
            try {
                resolver.openOutputStream(uri)?.use { outputStream ->
                    videoFile.inputStream().use { inputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }
                true
            } catch (e: IOException) {
                Log.e(TAG, "Failed to save video", e)
                false
            }
        } else {
            false
        }
    }
    
    private fun saveVideoToGalleryLegacy(videoFile: File, videoName: String): Boolean {
        val moviesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        val nosmaiDir = File(moviesDir, "Nosmai")
        if (!nosmaiDir.exists()) {
            nosmaiDir.mkdirs()
        }
        
        val destFile = File(nosmaiDir, "$videoName.mp4")
        return try {
            videoFile.copyTo(destFile, overwrite = true)
            
            // Notify gallery about the new video
            val mediaScanIntent = android.content.Intent(android.content.Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            mediaScanIntent.data = android.net.Uri.fromFile(destFile)
            context.sendBroadcast(mediaScanIntent)
            
            true
        } catch (e: IOException) {
            Log.e(TAG, "Failed to save video", e)
            false
        }
    }

    // --- SDK Cleanup and Management ---
    private fun handleCleanup(result: Result) {
        try {
            if (isSdkInitialized) {
                // Clean up SDK resources while preserving initialization state
                // Similar to iOS, we don't set isInitialized to false
                try {
                    // Stop any active processing
                    if (isProcessingActive) {
                        NosmaiSDK.stopProcessing()
                        isProcessingActive = false
                    }
                    
                    // Camera is managed by SDK; no explicit Camera2 helper
                    
                    // Clear any active filters/effects
                    NosmaiEffects.removeEffect()
                    NosmaiBeauty.removeAllBeautyFilters()
                    
                    // Clear render surface temporarily to release resources
                    NosmaiSDK.clearRenderSurface()
                    
                    // Don't release texture/surface here - keep them for reuse
                    // Just reset the binding flag
                    surfaceReboundOnce = false
                    
                    // Clean up recording if active
                    if (isRecording) {
                        try {
                            com.nosmai.effect.api.NosmaiSDK.stopRecording(object : com.nosmai.effect.api.NosmaiSDK.RecordingCallback {
                                override fun onCompleted(outputPath: String?, success: Boolean, error: String?) {
                                    // Ignore result, just cleanup
                                }
                            })
                            isRecording = false
                        } catch (_: Throwable) {}
                    }
                } catch (e: Throwable) {
                    Log.w(TAG, "Cleanup warning", e)
                }
            }
            
            // Don't clear filter cache on every cleanup - only on full disposal
            
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "Cleanup error", t)
            result.error("CLEANUP_ERROR", t.message, null)
        }
    }
    
    private fun handleClearFilterCache(result: Result) {
        try {
            clearFilterCache()
            result.success(null)
        } catch (t: Throwable) {
            Log.e(TAG, "Clear filter cache error", t)
            result.error("CLEAR_CACHE_ERROR", t.message, null)
        }
    }
    
    private fun clearFilterCache() {
        try {
            // Clear cached filter files
            val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
            if (cacheDir.exists() && cacheDir.isDirectory) {
                cacheDir.listFiles()?.forEach { file ->
                    if (file.name.endsWith(".nosmai")) {
                        file.delete()
                    }
                }
            }
            
            // Clear downloaded cloud filters cache
            val cloudCacheDir = File(context.filesDir, "cloud_filters")
            if (cloudCacheDir.exists() && cloudCacheDir.isDirectory) {
                cloudCacheDir.listFiles()?.forEach { file ->
                    file.delete()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to clear filter cache", e)
        }
    }
    
    private fun handleReinitializePreview(result: Result) {
        try {
            // Don't try to reinitialize if we don't have valid texture/surface
            if (textureEntry == null || surface == null) {
                result.success(null)
                return
            }
            
            // Clear the SDK render surface first
            try {
                NosmaiSDK.clearRenderSurface()
            } catch (_: Throwable) {}
            
            // Small delay to ensure cleanup
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    // Only proceed if we still have valid references
                    val entry = textureEntry
                    val surf = surface
                    if (entry != null && surf != null && !surf.isValid) {
                        // Surface is invalid, need to recreate
                        val st = entry.surfaceTexture()
                        val w = pendingSurfaceWidth ?: 720
                        val h = pendingSurfaceHeight ?: 1280
                        st.setDefaultBufferSize(w, h)
                        surface = Surface(st)
                    }
                    
                    // Set render surface if we have a valid one
                    surface?.let { s ->
                        if (s.isValid) {
                            val w = pendingSurfaceWidth ?: 720
                            val h = pendingSurfaceHeight ?: 1280
                            NosmaiSDK.setRenderSurface(s, w, h)
                            NosmaiSDK.setMirrorX(isFrontCamera)
                            surfaceReboundOnce = false
                        }
                    }
                    result.success(null)
                } catch (e: Throwable) {
                    Log.e(TAG, "Failed to reinitialize preview", e)
                    // Don't error, just return success
                    result.success(null)
                }
            }, 100)
        } catch (t: Throwable) {
            Log.e(TAG, "Reinitialize preview error", t)
            // Don't error, just return success
            result.success(null)
        }
    }

    // --- Helpers ---
    private fun readAssetText(assetPath: String): String? {
        return try {
            context.assets.open(assetPath).use { ins ->
                ins.bufferedReader(Charsets.UTF_8).readText()
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun ensureAssetCached(assetPath: String): File? {
        return try {
            val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
            if (!cacheDir.exists()) cacheDir.mkdirs()

            val fileName = File(assetPath).name // keep original file name
            val outFile = File(cacheDir, fileName)

            if (!outFile.exists() || outFile.length() == 0L) {
                // Copy asset into cache file
                openAnyAsset(assetPath).use { ins ->
                    FileOutputStream(outFile).use { fos ->
                        ins.copyTo(fos)
                    }
                }
            }
            outFile
        } catch (e: Exception) {
            Log.w(TAG, "Failed to cache asset: $assetPath", e)
            null
        }
    }

    private fun openAnyAsset(assetPath: String): InputStream {
        // Try exact path first, then prefixed with flutter_assets/
        return try {
            context.assets.open(assetPath)
        } catch (_: Exception) {
            val candidate = if (assetPath.startsWith("flutter_assets/")) assetPath else "flutter_assets/$assetPath"
            context.assets.open(candidate)
        }
    }

    private fun toTitleCase(name: String): String {
        val cleaned = name.replace('_', ' ').replace('-', ' ')
        return cleaned.split(" ")
            .filter { it.isNotBlank() }
            .joinToString(" ") { it.replaceFirstChar { c -> c.titlecase() } }
    }

    private fun extractManifestFieldsFromNosmai(filterName: String): Quad<String?, String?, String?, Boolean> {
        // Tries multiple asset roots: flutter_assets/assets/filters/, assets/filters/, filters/
        val candidates = listOf(
            "flutter_assets/assets/filters/$filterName.nosmai",
            "assets/filters/$filterName.nosmai",
            "filters/$filterName.nosmai"
        )
        var ftype: String? = null
        var display: String? = null
        var desc: String? = null
        var hasPrev = false
        for (p in candidates) {
            try {
                val cls = Class.forName("com.nosmai.effect.internal.NosmaiFilter")
                val m = cls.getMethod("nativeExtractManifestFromAssets", Context::class.java, String::class.java)
                val jsonStr = m.invoke(null, context, p) as? String
                if (!jsonStr.isNullOrBlank()) {
                    val json = JSONObject(jsonStr)
                    val t = (json.optString("filterType", json.optString("type", ""))).lowercase()
                    if (t == "filter" || t == "effect") ftype = t
                    display = json.optString("displayName", display)
                    desc = json.optString("description", desc)
                    if (json.has("preview")) hasPrev = true
                    break
                }
            } catch (_: Throwable) { }
        }
        return Quad(ftype, display, desc, hasPrev)
    }

    private fun tryExtractPreviewBase64(filterName: String): String? {
        val candidates = listOf(
            "flutter_assets/assets/filters/$filterName.nosmai",
            "assets/filters/$filterName.nosmai",
            "filters/$filterName.nosmai"
        )
        for (p in candidates) {
            try {
                val cls = Class.forName("com.nosmai.effect.internal.NosmaiFilter")
                val m = cls.getMethod("nativeExtractPreviewFromAssets", Context::class.java, String::class.java)
                val bmp = m.invoke(null, context, p) as? Bitmap
                if (bmp != null) {
                    return bitmapToBase64(bmp)
                }
            } catch (_: Throwable) { }
        }
        return null
    }

    data class Quad<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)

    private fun tryLoadPreviewBase64(file: File?): String? {
        if (file == null || !file.exists()) return null
        // Best-effort: use SDK if it exposes a preview API; otherwise skip
        return try {
            // If SDK has a direct preview method, add here. Placeholder returns null.
            null
        } catch (_: Throwable) { null }
    }

    private fun tryGetFilterType(file: File?): String? {
        // If SDK can inspect filter type on Android, plug it here. Default to effect.
        return null
    }

    private fun bitmapToBase64(bmp: Bitmap): String {
        val baos = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 70, baos)
        val data = baos.toByteArray()
        return Base64.encodeToString(data, Base64.NO_WRAP)
    }

    private fun resolveEffectToFile(effectPathArg: String): File? {
        val arg = effectPathArg.trim()

        // 1) If already a file path
        val direct = File(arg)
        if (direct.exists()) return direct

        // 2) If looks like asset full path (with or without flutter_assets prefix)
        val assetCandidates = mutableListOf<String>()
        if (arg.startsWith(FILTERS_PREFIX)) {
            assetCandidates.add("flutter_assets/$arg")
            assetCandidates.add(arg) // sometimes packed directly
        } else if (arg.startsWith("filters/")) {
            // Direct engine-style asset path
            assetCandidates.add("flutter_assets/$arg")
            assetCandidates.add(arg)
        } else {
            // Treat as filter name or relative path
            val name = if (arg.endsWith(".nosmai")) arg.substringBeforeLast(".nosmai") else arg
            assetCandidates.add("flutter_assets/${FILTERS_PREFIX}${name}.nosmai")
            assetCandidates.add("${FILTERS_PREFIX}${name}.nosmai")
            assetCandidates.add("flutter_assets/filters/${name}.nosmai")
            assetCandidates.add("filters/${name}.nosmai")
        }

        for (asset in assetCandidates) {
            try {
                context.assets.open(asset).use { _ ->
                    val cached = ensureAssetCached(asset)
                    if (cached != null && cached.exists()) return cached
                }
            } catch (_: Exception) {
                // try next
            }
        }

        // 3) Try via AssetManifest.json lookup
        val manifestJson = readAssetText(ASSET_MANIFEST_PATH)
        if (manifestJson != null) {
            val manifest = JSONObject(manifestJson)
            val keys = manifest.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (key.startsWith(FILTERS_PREFIX) && key.endsWith(".nosmai")) {
                    val name = File(key).nameWithoutExtension
                    if (name.equals(arg, ignoreCase = true)) {
                        val cached = ensureAssetCached("flutter_assets/$key") ?: ensureAssetCached(key)
                        if (cached != null && cached.exists()) return cached
                    }
                }
            }
        }

        return null
    }

    // ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        activityBinding?.addRequestPermissionsResultListener(this)
        // If init was requested before activity was available, complete it now
        val key = pendingLicenseKey
        if (key != null && !isSdkInitialized) {
            try { initializeSdk(binding.activity, key) } catch (_: Throwable) {}
            pendingLicenseKey = null
        }
    }
    override fun onDetachedFromActivityForConfigChanges() { activity = null; activityBinding = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity; activityBinding = binding }
    override fun onDetachedFromActivity() { activity = null; activityBinding = null }

    // Permissions and camera start like backup
    private fun ensureCameraPermissionThenStart() {
        val act = activity ?: return
        if (ContextCompat.checkSelfPermission(act, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            activityBinding?.addRequestPermissionsResultListener(this)
            ActivityCompat.requestPermissions(act, arrayOf(Manifest.permission.CAMERA), REQ_CAMERA)
        }
        // SDK manages camera internally during startProcessing
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode == REQ_CAMERA) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // Permission granted; SDK will handle camera when processing starts
            } else {
                Log.e(TAG, "Camera permission denied")
            }
            return true
        }
        return false
    }
}

package com.xdl.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.EventChannel
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    internal val shares = NativeShareGateway()
    private val executor = Executors.newSingleThreadExecutor()
    private val playbackControls by lazy { PlaybackWindowControls(this) }
    private val waitingForPermission = mutableListOf<Pair<MethodCall, MethodChannel.Result>>()
    private val notificationResults = mutableListOf<MethodChannel.Result>()
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        shares.accept(intent)
        super.onCreate(savedInstanceState)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shares.accept(intent)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "xdl/shared_text").setStreamHandler(shares)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xdl/platform")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestNotifications") {
                    val prefs = getSharedPreferences("xdl_flutter_permissions", 0)
                    if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED || prefs.getBoolean("notificationAsked", false)) {
                        result.success(getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled())
                    } else {
                        notificationResults.add(result)
                        if (notificationResults.size == 1) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
                    }
                } else if (call.method in listOf("enqueue", "publish") && Build.VERSION.SDK_INT < 29 &&
                    checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    waitingForPermission.add(call to result)
                    if (waitingForPermission.size == 1) requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE, Manifest.permission.READ_EXTERNAL_STORAGE), 40)
                } else dispatch(call, result)
            }
    }
    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        if (call.method.startsWith("update")) {
            dispatchUpdate(call, result)
            return
        }
        if (call.method in PlaybackWindowControls.methods) {
            try { result.success(playbackControls.handle(call.method, call.arguments)) }
            catch (e: Exception) { result.error("playback", e.message, null) }
            return
        }
        val store = NativeDownloads(applicationContext)
        if (ProbeGateway.handle(this, store, call, result)) return
        executor.execute {
            try {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val value: Any? = when (call.method) {
                    "supportDirectory" -> filesDir.absolutePath
                    "cacheDirectory" -> cacheDir.absolutePath
                    "notificationStatus" -> getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()
                    "initialShare" -> shares.initialText()
                    "readLegacy" -> LegacyDataGateway.read(applicationContext)
                    "locateOwnedDownload" -> LegacyDataGateway.locate(applicationContext, args["displayName"] as String)
                    "initialize" -> { store.snapshot(true); null }
                    "enqueue" -> { store.enqueue(args); null }
                    "snapshot" -> store.snapshot(true)
                    "rawSnapshot" -> store.snapshot(false)
                    "publish" -> jsonValue(store.publish(args["taskId"] as String))
                    "cancel" -> { store.cancel(args["taskId"] as String); null }
                    "discardStaging" -> { store.discard(args["taskId"] as String); null }
                    "open" -> { FileGateway.open(applicationContext, args["locator"] as String, args["mimeType"] as String); null }
                    "ensureReadable" -> { FileGateway.ensureReadable(applicationContext, args["locator"] as String); null }
                    "thumbnail" -> FileGateway.thumbnail(applicationContext, args["locator"] as String)
                    "deleteSavedFile" -> { FileGateway.deleteSavedFile(applicationContext, args["locator"] as String); null }
                    "openDirectory" -> { FileGateway.openDirectory(applicationContext); null }
                    else -> { result.notImplemented(); return@execute }
                }
                result.success(value)
            } catch (e: Exception) {
                result.error(if (e is java.io.FileNotFoundException) "fileMissing" else "storage", e.message, null)
            }
        }
    }
    private fun dispatchUpdate(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val updates = NativeAppUpdates(applicationContext)
        if (call.method == "updateOpenReleasePage") {
            try { UpdateInstallGateway.openPage(this, args["url"] as String); result.success(null) }
            catch (e: Exception) { result.error("update", e.message, null) }
            return
        }
        executor.execute {
            try {
                if (call.method == "updateInstall") {
                    val id = args["candidateId"] as String
                    val file = updates.verifiedFile(id)
                    runOnUiThread {
                        try {
                            if (!UpdateInstallGateway.install(this, file)) updates.permissionRequired(id)
                            executor.execute {
                                try { result.success(updates.snapshot()) }
                                catch (e: Exception) { result.error("update", e.message, null) }
                            }
                        } catch (e: Exception) { result.error("update", e.message, null) }
                    }
                    return@execute
                }
                val value: Any? = when (call.method) {
                    "updateInstalledApp" -> UpdatePackageVerifier.installedMap(applicationContext)
                    "updateSnapshot" -> updates.snapshot()
                    "updateEnqueue" -> { updates.enqueue(args); null }
                    "updateCancel" -> { updates.cancel(args["candidateId"] as String); null }
                    else -> { result.notImplemented(); return@execute }
                }
                result.success(value)
            } catch (e: Exception) { result.error("update", e.message, null) }
        }
    }
    override fun onDestroy() {
        playbackControls.end()
        super.onDestroy()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 41) {
            getSharedPreferences("xdl_flutter_permissions", 0).edit().putBoolean("notificationAsked", true).apply()
            val enabled = getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()
            val pending = notificationResults.toList(); notificationResults.clear()
            pending.forEach { it.success(enabled) }
        }
        if (requestCode == 40) {
            val pending = waitingForPermission.toList(); waitingForPermission.clear()
            pending.forEach { (call, result) ->
                if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) dispatch(call, result)
                else result.error("storage", "需要存储权限才能保存到公共下载目录", null)
            }
        }
    }
}

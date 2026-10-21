package com.xdl.app

import android.content.ContentUris
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Test-only fixture access. This class is excluded from production APKs. */
object ProbeGateway {
    fun handle(activity: MainActivity, store: NativeDownloads, call: MethodCall, result: MethodChannel.Result): Boolean {
        if (!call.method.startsWith("probe")) return false
        try {
            val a = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            val value: Any? = synchronized(NativeDownloads.lock) {
                when (call.method) {
                    "probeLoadUpdateFixtures" -> activity.assets.open("update_probe_fixtures.json").bufferedReader().use { it.readText() }
                    "probeCanInstallUpdates" -> activity.packageManager.canRequestPackageInstalls()
                    "probeReturnToApp" -> {
                        activity.startActivity(Intent(activity, MainActivity::class.java).setAction(Intent.ACTION_MAIN).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP))
                        null
                    }
                    "probeStageReadyUpdate" -> {
                        require(activity.packageName.endsWith(".probe"))
                        val data = Base64.decode(a["data"] as String, Base64.DEFAULT)
                        require(data.size < 1024 * 1024)
                        val expected = JSONObject(a["expected"] as Map<*, *>)
                        val hash = expected.getJSONObject("asset").getString("sha256")
                        require(hash.matches(Regex("[a-f0-9]{64}")))
                        expected.getJSONObject("asset").put("url", "https://github.com/ThermalEX/XDownloader/releases/download/v2.5.0/probe.apk")
                        val folder = java.io.File(activity.getExternalFilesDir(null), "xdl-updates").apply { mkdirs() }
                        java.io.File(folder, "$hash.apk").writeBytes(data)
                        expected.put("candidateId", "probe-stage").put("phase", if (a["permissionRequired"] == true) "permissionRequired" else "ready").put("bytes", data.size)
                        val state = android.util.AtomicFile(java.io.File(activity.filesDir, "app_update.json"))
                        val stream = state.startWrite()
                        stream.write(expected.toString().toByteArray()); state.finishWrite(stream)
                        NativeAppUpdates(activity).snapshot()
                    }
                    "probeClearReadyUpdate" -> {
                        require(activity.packageName.endsWith(".probe"))
                        val state = android.util.AtomicFile(java.io.File(activity.filesDir, "app_update.json"))
                        if (state.baseFile.exists()) {
                            val payload = state.openRead().bufferedReader().use { JSONObject(it.readText()) }
                            require(payload.getString("candidateId") == "probe-stage")
                            NativeAppUpdates(activity).cancel("probe-stage")
                            java.io.File(activity.cacheDir, "xdl-install/${payload.getJSONObject("asset").getString("sha256")}.apk").delete()
                            state.delete()
                        }
                        null
                    }
                    "probeVerifyUpdate" -> {
                        require(activity.packageName.endsWith(".probe"))
                        val data = Base64.decode(a["data"] as String, Base64.DEFAULT)
                        require(data.size <= 1024 * 1024) { "probe fixture too large" }
                        val expected = JSONObject(a["expected"] as Map<*, *>)
                        val file = java.io.File(activity.cacheDir, "xdl_probe_update.apk")
                        try {
                            file.writeBytes(data)
                            UpdatePackageVerifier.verify(activity, file, expected)
                            if (a["replaceAfterVerification"] == true) {
                                file.writeBytes(byteArrayOf(1, 2, 3))
                                UpdatePackageVerifier.verify(activity, file, expected)
                            }
                            val folder = java.io.File(activity.cacheDir, "xdl-install").apply { mkdirs() }
                            val staged = java.io.File(folder, "xdl_probe_update.apk")
                            try {
                                file.copyTo(staged, overwrite = true)
                                val intent = UpdateInstallGateway.installerIntent(activity, staged)
                                mapOf("verified" to true, "uri" to intent.data.toString(), "mimeType" to intent.type,
                                    "grantRead" to (intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0))
                            } finally { staged.delete() }
                        } finally { file.delete() }
                    }
                    "probeUpdateRecovery" -> {
                        require(activity.packageName.endsWith(".probe"))
                        val manager = activity.getSystemService(android.app.DownloadManager::class.java)
                        val hash = "1".repeat(64)
                        val root = java.io.File(activity.getExternalFilesDir(null), "xdl-updates").apply { mkdirs() }
                        val destination = java.io.File(root, "$hash.apk")
                        val unrelated = java.io.File(activity.cacheDir, "xdl_probe_unrelated.mp4")
                        val state = android.util.AtomicFile(java.io.File(activity.filesDir, "app_update.json"))
                        require(!state.baseFile.exists()) { "probe update state already exists" }
                        val uri = android.net.Uri.parse("https://video.twimg.com/amplify_video/1655498815133335553/vid/320x568/hf7SEZqvRAUkWsTK.mp4?tag=16")
                        var updateId = -1L
                        var videoId = -1L
                        try {
                            // Separate destinations model a video transfer and an interrupted update enqueue.
                            val video = java.io.File(activity.getExternalFilesDir(null), "xdl_probe_unrelated.mp4")
                            if (video.exists()) video.delete()
                            videoId = manager.enqueue(android.app.DownloadManager.Request(uri).setDestinationUri(android.net.Uri.fromFile(video)))
                            if (destination.exists()) destination.delete()
                            updateId = manager.enqueue(android.app.DownloadManager.Request(uri).setTitle("XDownloader 2.5.0").setDestinationUri(android.net.Uri.fromFile(destination)))
                            val payload = JSONObject().put("candidateId", "probe-recovery").put("versionCode", 999999)
                                .put("phase", "queued").put("bytes", 0).put("packageName", activity.packageName).put("versionName", "2.5.0")
                                .put("asset", JSONObject().put("sha256", hash).put("bytes", 1024 * 1024).put("url", uri.toString()))
                            val stream = state.startWrite()
                            stream.write(payload.toString().toByteArray()); state.finishWrite(stream)
                            val updates = NativeAppUpdates(activity)
                            updates.snapshot()
                            val recovered = state.openRead().bufferedReader().use { JSONObject(it.readText()).getLong("downloadId") }
                            updates.cancel("probe-recovery")
                            val preserved = manager.query(android.app.DownloadManager.Query().setFilterById(videoId)).use { it.moveToFirst() }
                            mapOf("recovered" to (recovered == updateId), "videoPreserved" to preserved,
                                "updateRemoved" to !manager.query(android.app.DownloadManager.Query().setFilterById(updateId)).use { it.moveToFirst() })
                        } finally {
                            if (updateId >= 0) manager.remove(updateId)
                            if (videoId >= 0) manager.remove(videoId)
                            state.delete(); destination.delete(); unrelated.delete()
                            java.io.File(activity.getExternalFilesDir(null), "xdl_probe_unrelated.mp4").delete()
                        }
                    }
                    "probeDeviceLocked" -> activity.getSystemService(android.app.KeyguardManager::class.java).isDeviceLocked
                    "probeCleanupOrphanFixtures" -> {
                        val manager = activity.getSystemService(android.app.DownloadManager::class.java)
                        val root = java.io.File(activity.getExternalFilesDir(null), "xdl-staging").absolutePath + "/"
                        val live = store.records().map { it.getString("taskId") }.toSet()
                        val orphanIds = mutableListOf<Long>()
                        manager.query(android.app.DownloadManager.Query()).use { c ->
                            while (c.moveToNext()) {
                                val title = c.getString(c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_TITLE)) ?: ""
                                val path = c.getString(c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_LOCAL_URI))?.let { android.net.Uri.parse(it).path } ?: ""
                                val task = if (path.isEmpty()) Regex("^xdl_probe_([a-f0-9]{32})").find(title)?.groupValues?.get(1) ?: ""
                                    else java.io.File(path).nameWithoutExtension
                                if (title.startsWith("xdl_probe_") && (path.isEmpty() || path.startsWith(root)) && task.matches(Regex("[a-f0-9]{32}")) && task !in live) {
                                    orphanIds.add(c.getLong(c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_ID)))
                                }
                            }
                        }
                        orphanIds.forEach { manager.remove(it) }
                        orphanIds.size
                    }
                    "probeInterruptEnqueue" -> {
                        val id = a["taskId"] as String
                        if (a["beforeSystem"] == true) {
                            store.save(JSONObject().put("taskId", id).put("request", JSONObject(a))
                                .put("url", a["url"]).put("displayName", a["displayName"])
                                .put("stagingPath", store.staging(id).path).put("phase", "queued")
                                .put("bytes", 0).put("jobId", 99999))
                        } else {
                            store.enqueue(a)
                            val r = store.record(id)
                            val nativeId = r.getLong("downloadId")
                            activity.getSystemService(android.app.DownloadManager::class.java).query(android.app.DownloadManager.Query().setFilterById(nativeId)).use { c ->
                                if (c.moveToFirst()) android.util.Log.i("XdlProbe", "orphan destination=" + c.getString(c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_LOCAL_URI)) + " expected=" + r.getString("stagingPath"))
                            }
                            r.remove("downloadId"); store.save(r)
                        }
                        null
                    }
                    "probeReplaceLegacy" -> {
                        fun replace(name: String, values: Map<*, *>) {
                            val edit = activity.getSharedPreferences(name, 0).edit().clear()
                            values.forEach { (key, value) -> when (value) {
                                is String -> edit.putString(key as String, value)
                                is Boolean -> edit.putBoolean(key as String, value)
                                is Number -> edit.putLong(key as String, value.toLong())
                            } }
                            check(edit.commit())
                        }
                        replace("xdl_sources", a["sources"] as Map<*, *>)
                        replace("xdl_settings", a["settings"] as Map<*, *>)
                        replace("xdl_history", if (a["historyJson"] == null) emptyMap<String, String>() else mapOf("items" to a["historyJson"]))
                        null
                    }
                    "probePrepareInitialShare" -> {
                        val intent = Intent(Intent.ACTION_SEND).setType("text/plain")
                        if (a["text"] is String) intent.putExtra(Intent.EXTRA_TEXT, a["text"] as String)
                        activity.shares.accept(intent); null
                    }
                    "probeSendShare" -> {
                        val intent = Intent(activity, MainActivity::class.java).setAction(Intent.ACTION_SEND).setType("text/plain")
                            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        if (a["text"] is String) intent.putExtra(Intent.EXTRA_TEXT, a["text"] as String)
                        activity.startActivity(intent); null
                    }
                    "probeSeed" -> {
                        val id = a["taskId"] as String
                        val source = store.staging(id)
                        val bytes = Base64.decode(a["data"] as String, Base64.DEFAULT)
                        source.writeBytes(bytes)
                        store.save(JSONObject().put("taskId", id).put("displayName", a["displayName"])
                            .put("stagingPath", source.path).put("phase", "transferred").put("bytes", bytes.size)
                            .put("totalBytes", bytes.size).put("mimeType", a["mimeType"])
                            .put("statusCode", a["statusCode"]).put("forceFailure", a["forceFailure"]))
                        null
                    }
                    "probeAllowPublish" -> { store.save(store.record(a["taskId"] as String).put("forceFailure", false)); null }
                    "probeLoseReceipt" -> {
                        val r = store.record(a["taskId"] as String)
                        val uri = android.net.Uri.parse(r.getJSONObject("savedFile").getString("locator"))
                        activity.contentResolver.openInputStream(uri)!!.use { input ->
                            java.io.File(r.getString("stagingPath")).outputStream().use { input.copyTo(it) }
                        }
                        r.remove("savedFile"); store.save(r)
                        null
                    }
                    "probeRemoveSavedFile" -> {
                        val r = store.record(a["taskId"] as String)
                        check(r.getString("displayName").startsWith("xdl_probe_"))
                        activity.contentResolver.delete(android.net.Uri.parse(r.getJSONObject("savedFile").getString("locator")), null, null)
                        null
                    }
                    "probeInspect" -> {
                        val r = store.record(a["taskId"] as String)
                        val name = r.getString("displayName")
                        val saved = r.optJSONObject("savedFile")
                        val out = mutableMapOf<String, Any?>("stagingExists" to java.io.File(r.getString("stagingPath")).exists(), "publicCount" to 0)
                        val notifications = activity.getSystemService(android.app.NotificationManager::class.java)
                        out["notificationsEnabled"] = notifications.areNotificationsEnabled()
                        out["savedNotification"] = notifications.activeNotifications.any { it.tag == r.getString("taskId") }
                        if (r.has("downloadId")) activity.getSystemService(android.app.DownloadManager::class.java)
                            .query(android.app.DownloadManager.Query().setFilterById(r.getLong("downloadId"))).use {
                                out["nativeTransferExists"] = it.moveToFirst()
                            }
                        if (Build.VERSION.SDK_INT >= 29) {
                            activity.contentResolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.RELATIVE_PATH),
                                "${MediaStore.MediaColumns.DISPLAY_NAME}=?", arrayOf(name), null)?.use {
                                out["publicCount"] = it.count
                                if (it.moveToFirst()) out["relativePath"] = it.getString(1)
                            }
                        }
                        if (saved != null) activity.contentResolver.openInputStream(android.net.Uri.parse(saved.getString("locator")))?.use {
                            out["data"] = Base64.encodeToString(it.readBytes(), Base64.NO_WRAP)
                        }
                        out
                    }
                    "probeDelete" -> {
                        val id = a["taskId"] as String
                        val r = try { store.record(id) } catch (_: Exception) { null }
                        if (r != null) {
                            check(r.getString("displayName").startsWith("xdl_probe_"))
                            store.cancel(id)
                            val uri = r.optJSONObject("savedFile")?.optString("locator") ?: r.optString("pendingUri")
                            if (uri.isNotEmpty()) activity.contentResolver.delete(android.net.Uri.parse(uri), null, null)
                            java.io.File(r.getString("stagingPath")).delete()
                            activity.getSharedPreferences("xdl_native_downloads", 0).edit().remove("task_$id").commit()
                            activity.getSystemService(android.app.NotificationManager::class.java).cancel(id, 1)
                        }
                        null
                    }
                    "probeBackground" -> { activity.moveTaskToBack(true); null }
                    "probeForeground" -> { activity.startActivity(Intent(activity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)); null }
                    else -> { result.notImplemented(); return true }
                }
            }
            result.success(value)
        } catch (e: Exception) { result.error("probe", e.toString(), null) }
        return true
    }
}

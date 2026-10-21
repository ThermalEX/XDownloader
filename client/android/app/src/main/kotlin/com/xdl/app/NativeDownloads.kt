package com.xdl.app

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.content.ContentValues
import androidx.core.content.FileProvider
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.io.FileOutputStream

/** One lock protects cancellation, publication and durable receipts across jobs and UI. */
class NativeDownloads(val context: Context) {
    companion object {
        val lock = Any()
        private fun filenameBase(raw: String): String {
            val clean = raw.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").removeSuffix(".mp4")
            val result = StringBuilder()
            var offset = 0
            var bytes = 0
            while (offset < clean.length) {
                val point = Character.codePointAt(clean, offset)
                offset += Character.charCount(point)
                val safe = if (point in 0xD800..0xDFFF) '_'.code else point
                val size = when {
                    safe <= 0x7F -> 1
                    safe <= 0x7FF -> 2
                    safe <= 0xFFFF -> 3
                    else -> 4
                }
                // Match Dart's stem budget while preserving the unique task suffix.
                if (bytes + size > 176) break
                result.appendCodePoint(safe)
                bytes += size
            }
            return result.toString().ifBlank { "video" }
        }
    }
    private val prefs = context.getSharedPreferences("xdl_native_downloads", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(DownloadManager::class.java)
    private val resolver = context.contentResolver
    fun records(): List<JSONObject> = prefs.all.filterKeys { it.startsWith("task_") }.values.mapNotNull {
        try { JSONObject(it as String) } catch (_: Exception) { null }
    }
    fun record(id: String): JSONObject = prefs.getString("task_$id", null)?.let { JSONObject(it) }
        ?: throw IllegalStateException("Unknown task: $id")
    fun save(r: JSONObject) {
        check(prefs.edit().putString("task_${r.getString("taskId")}", r.toString()).commit()) { "Cannot persist task" }
    }
    fun staging(id: String): File {
        require(id.matches(Regex("[a-f0-9]{32}"))) { "Invalid task ID" }
        return File(context.getExternalFilesDir(null), "xdl-staging/$id.mp4").also { it.parentFile!!.mkdirs() }
    }
    fun enqueue(args: Map<*, *>) = synchronized(lock) {
        val id = args["taskId"] as String
        if (prefs.contains("task_$id")) return@synchronized
        val url = Uri.parse(args["url"] as String)
        require(url.scheme in listOf("http", "https") && !url.host.isNullOrEmpty()) { "Invalid download URL" }
        val source = staging(id)
        val base = filenameBase(args["displayName"] as String)
        val job = prefs.getInt("next_job", 1000)
        check(prefs.edit().putInt("next_job", job + 1).commit())
        val r = JSONObject().put("taskId", id).put("url", url.toString())
            .put("request", JSONObject(args))
            .put("displayName", "${base}_$id.mp4").put("stagingPath", source.path)
            .put("phase", "queued").put("bytes", 0).put("jobId", job)
        save(r)
        try {
            val request = DownloadManager.Request(url).setTitle(r.getString("displayName"))
                .setDescription("正在传输，完成后保存到 Download/XDownloader")
                .setDestinationUri(Uri.fromFile(source))
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                .setAllowedOverMetered(true).setAllowedOverRoaming(true)
            (args["headers"] as? Map<*, *>)?.forEach { (k, v) -> request.addRequestHeader(k as String, v as String) }
            val nativeId = manager.enqueue(request)
            try { save(r.put("downloadId", nativeId)) }
            catch (e: Exception) { manager.remove(nativeId); throw e }
        } catch (e: Exception) {
            save(r.put("phase", "failed").put("error", e.message))
            throw e
        }
    }
    fun refresh(r: JSONObject, publish: Boolean = true) {
        if (r.has("savedFile")) { cleanupTransfer(r); return }
        if (r.optString("phase") == "cancelled") return
        if (r.optString("phase") == "failed") return // Explicit repository retry handles storage failures.
        val nativeId = recoverTransfer(r)
        if (nativeId < 0) {
            save(r.put("phase", "failed").put("error", "下载入队被中断，请重试")); return
        }
        manager.query(DownloadManager.Query().setFilterById(nativeId)).use { c ->
            if (!c.moveToFirst()) {
                save(r.put("phase", "failed").put("error", "系统下载任务已不存在")); return
            }
            fun long(name: String) = c.getLong(c.getColumnIndexOrThrow(name))
            val bytes = long(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val total = long(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            r.put("bytes", bytes)
            if (total >= 0) r.put("totalBytes", total)
            when (long(DownloadManager.COLUMN_STATUS).toInt()) {
                DownloadManager.STATUS_SUCCESSFUL -> {
                    r.put("phase", "transferred").put("statusCode", 200)
                    r.put("mimeType", c.getString(c.getColumnIndexOrThrow(DownloadManager.COLUMN_MEDIA_TYPE)))
                    save(r)
                    if (publish) try { publishRecord(r) } catch (e: Exception) { fail(r, e) }
                }
                DownloadManager.STATUS_FAILED -> save(r.put("phase", "failed")
                    .put("error", "系统下载失败 (${long(DownloadManager.COLUMN_REASON)})"))
                DownloadManager.STATUS_PENDING -> transition(r, "queued")
                else -> transition(r, "running")
            }
        }
    }
    private fun recoverTransfer(r: JSONObject): Long {
        if (r.has("downloadId")) return r.getLong("downloadId")
        // The destination and reserved filename are durable before enqueue.
        // Android may return null local_uri while a transfer is still pending;
        // the owner-scoped title then identifies its full task-ID filename.
        val path = File(r.getString("stagingPath")).absolutePath
        manager.query(DownloadManager.Query()).use { c ->
            val local = c.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
            val id = c.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
            val title = c.getColumnIndexOrThrow(DownloadManager.COLUMN_TITLE)
            while (c.moveToNext()) {
                val uri = c.getString(local)?.let { Uri.parse(it) }
                val matches = if (uri?.scheme == "file") uri.path == path
                    else c.getString(title) == r.getString("displayName")
                if (matches) {
                    val nativeId = c.getLong(id)
                    save(r.put("downloadId", nativeId))
                    return nativeId
                }
            }
        }
        return -1
    }
    private fun transition(r: JSONObject, phase: String) {
        val changed = r.optString("phase") != phase
        r.put("phase", phase)
        // DownloadManager already persists byte progress; avoid a disk sync on every poll.
        if (changed) save(r)
    }
    fun fail(r: JSONObject, e: Exception) { save(r.put("phase", "failed").put("error", e.message ?: e.javaClass.simpleName)) }
    fun snapshot(reconcile: Boolean): List<Any?> = synchronized(lock) {
        val all = records()
        if (reconcile) all.forEach { refresh(it) }
        all.map { jsonValue(it) }
    }
    fun complete(nativeId: Long) = synchronized(lock) {
        if (nativeId < 0) return@synchronized
        records().firstOrNull {
            it.optLong("downloadId", -1) == nativeId ||
                (!it.has("downloadId") && it.optString("phase") in listOf("queued", "running") && recoverTransfer(it) == nativeId)
        }?.let {
            PublicationJob.schedule(context, it.getString("taskId"), it.getInt("jobId"))
        }
    }
    fun process(id: String) = synchronized(lock) { refresh(record(id)) }
    fun publish(id: String): JSONObject = synchronized(lock) {
        val r = record(id)
        if (r.optString("phase") == "cancelled") throw IllegalStateException("Task cancelled")
        try { publishRecord(r) } catch (e: Exception) { fail(r, e); throw e }
    }
    private fun receipt(r: JSONObject, locator: String, bytes: Long): JSONObject = JSONObject()
        .put("locator", locator).put("displayName", r.getString("displayName"))
        .put("bytes", bytes).put("mimeType", r.optString("mimeType", "video/mp4"))
    private fun finish(r: JSONObject, file: JSONObject): JSONObject {
        r.put("savedFile", file).put("phase", "transferred").put("bytes", file.getLong("bytes"))
        r.remove("error")
        save(r) // Receipt must be durable before staging can be discarded.
        File(r.getString("stagingPath")).delete()
        cleanupTransfer(r)
        try { SavedNotifications.show(context, r.getString("taskId"), file.getString("displayName")) }
        catch (e: Exception) { android.util.Log.w("XDownloader", "Saved notification unavailable", e) }
        return file
    }
    private fun cleanupTransfer(r: JSONObject) {
        if (!r.has("downloadId") || r.optBoolean("transferCleaned")) return
        try {
            manager.remove(r.getLong("downloadId")) // Only staging belongs to DownloadManager.
            save(r.put("transferCleaned", true))
        } catch (e: Exception) { android.util.Log.w("XDownloader", "Staging transfer cleanup will retry", e) }
    }
    private fun publishRecord(r: JSONObject): JSONObject {
        r.optJSONObject("savedFile")?.let { return it }
        val source = File(r.getString("stagingPath"))
        val name = r.getString("displayName")
        val bytes = source.length()
        check(r.optInt("statusCode") in 200..299) { "HTTP transfer was not successful" }
        check(bytes > 0) { "视频文件为空" }
        check(!r.has("totalBytes") || r.getLong("totalBytes") == bytes) { "视频文件不完整" }
        val header = ByteArray(12)
        val n = source.inputStream().use { it.read(header) }
        check(n >= 8 && String(header, 4, 4, Charsets.US_ASCII) == "ftyp") { "响应不是 MP4 视频" }
        val mime = r.optString("mimeType", "video/mp4").substringBefore(';')
        check(mime.startsWith("video/") || mime in listOf("application/octet-stream", "")) { "响应不是视频类型" }
        r.put("mimeType", "video/mp4")
        r.put("canPublish", true); save(r)
        check(!r.optBoolean("forceFailure")) { "Simulated storage failure" }
        if (Build.VERSION.SDK_INT >= 29) {
            var uri = r.optString("pendingUri").takeIf { it.isNotEmpty() }?.let { Uri.parse(it) }
            // Recover a crash between insert and saving pendingUri using the reserved unique name.
            if (uri == null) resolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID), "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                arrayOf(name, "Download/XDownloader/"), null)?.use { c ->
                if (c.moveToFirst()) uri = android.content.ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, c.getLong(0))
            }
            if (uri != null) {
                var pending = true; var size = -1L
                resolver.query(uri!!, arrayOf(MediaStore.MediaColumns.IS_PENDING, MediaStore.MediaColumns.SIZE), null, null, null)?.use { c ->
                    if (c.moveToFirst()) { pending = c.getInt(0) != 0; size = c.getLong(1) } else uri = null
                }
                if (!pending && size == bytes) return finish(r, receipt(r, uri.toString(), bytes))
            }
            if (uri == null) uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/XDownloader/")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }) ?: throw IllegalStateException("Cannot create public download")
            r.put("pendingUri", uri.toString()); save(r)
            // On failure the pending row and original staging remain recoverable.
            resolver.openFileDescriptor(uri!!, "rwt")!!.use { fd ->
                FileOutputStream(fd.fileDescriptor).use { output ->
                    source.inputStream().use { it.copyTo(output) }; output.flush(); output.fd.sync()
                }
            }
            resolver.openAssetFileDescriptor(uri!!, "r")!!.use { check(it.length == bytes) { "Public file length mismatch" } }
            check(resolver.update(uri!!, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1)
            return finish(r, receipt(r, uri.toString(), bytes))
        }
        val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "XDownloader").also { it.mkdirs() }
        val target = File(directory, name)
        if (!target.exists()) {
            val partial = File(directory, ".pending-${r.getString("taskId")}")
            FileOutputStream(partial).use { output -> source.inputStream().use { it.copyTo(output) }; output.fd.sync() }
            check(partial.length() == bytes && partial.renameTo(target)) { "Cannot publish download" }
        }
        check(target.length() == bytes) { "Public file length mismatch" }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", target)
        return finish(r, receipt(r, uri.toString(), bytes))
    }
    fun cancel(id: String) = synchronized(lock) {
        val r = record(id)
        if (r.has("savedFile")) return@synchronized
        recoverTransfer(r) // Cancellation also closes the interrupted-enqueue window.
        // A committed public row must not be removed even if a process died before its receipt.
        if (r.has("pendingUri") && Build.VERSION.SDK_INT >= 29) {
            var committed = false
            resolver.query(Uri.parse(r.getString("pendingUri")), arrayOf(MediaStore.MediaColumns.IS_PENDING), null, null, null)?.use {
                committed = it.moveToFirst() && it.getInt(0) == 0
            }
            if (committed) { publishRecord(r); return@synchronized }
        }
        save(r.put("phase", "cancelled"))
        if (r.has("downloadId")) manager.remove(r.getLong("downloadId"))
        r.optString("pendingUri").takeIf { it.isNotEmpty() }?.let { resolver.delete(Uri.parse(it), null, null) }
        File(r.getString("stagingPath")).delete()
        if (Build.VERSION.SDK_INT < 29) File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "XDownloader/.pending-$id").delete()
    }
    fun discard(id: String) = synchronized(lock) {
        val r = record(id)
        check(r.has("savedFile") || r.optString("phase") == "cancelled") { "Staging is still needed for recovery" }
        File(r.getString("stagingPath")).delete()
    }
}

fun jsonValue(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONObject -> value.keys().asSequence().associateWith { jsonValue(value.get(it)) }
    is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
    else -> value
}

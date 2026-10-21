package com.xdl.app

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Build
import android.util.AtomicFile
import java.io.File
import org.json.JSONObject

/** Separate from video transfers: own directory, lock, system IDs and state. */
class NativeAppUpdates(private val context: Context) {
    companion object { val lock = Any() }
    private val manager get() = context.getSystemService(DownloadManager::class.java)
    private val root get() = File(context.getExternalFilesDir(null), "xdl-updates").apply { check(mkdirs() || isDirectory) }
    private val stateFile get() = AtomicFile(File(context.filesDir, "app_update.json"))
    private fun read(): JSONObject? {
        val file = stateFile
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return null
        return file.openRead().bufferedReader().use { JSONObject(it.readText()) }
    }
    private fun save(state: JSONObject) {
        val file = stateFile
        val stream = file.startWrite()
        try { stream.write(state.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(stream) }
        catch (e: Exception) { file.failWrite(stream); throw e }
    }
    private fun destination(state: JSONObject): File {
        val hash = state.getJSONObject("asset").getString("sha256")
        require(hash.matches(Regex("[a-f0-9]{64}")))
        return File(root, "$hash.apk")
    }
    private fun recoverId(state: JSONObject): Long? {
        if (state.has("downloadId")) return state.getLong("downloadId")
        val expected = destination(state).absolutePath
        manager.query(DownloadManager.Query()).use { cursor ->
            while (cursor.moveToNext()) {
                val local = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                val uri = local?.let { Uri.parse(it) }
                val matches = if (uri?.scheme == "file") uri.path == expected else
                    cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TITLE)) == "XDownloader ${state.getString("versionName")}" &&
                    cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_URI)) == state.getJSONObject("asset").getString("url")
                if (matches) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID))
                    state.put("downloadId", id); save(state); return id
                }
            }
        }
        return null
    }
    fun enqueue(arguments: Map<*, *>) = synchronized(lock) {
        val next = JSONObject(arguments)
        val asset = next.getJSONObject("asset")
        val hash = asset.getString("sha256")
        require(hash.matches(Regex("[a-f0-9]{64}")) && asset.getLong("bytes") in 1..(200L * 1024 * 1024)) { "更新资产无效" }
        val uri = Uri.parse(asset.getString("url"))
        val tag = next.getString("tag")
        val name = asset.getString("name")
        require(name.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]*\\.apk"))) { "安装包名称无效" }
        require(uri.scheme == "https" && uri.host == "github.com" && uri.userInfo == null && uri.port == -1 && uri.query == null && uri.fragment == null &&
            uri.pathSegments == listOf("ThermalEX", "XDownloader", "releases", "download", tag, name)) { "更新地址无效" }
        require(next.getString("packageName") == context.packageName && next.getLong("versionCode") > (UpdatePackageVerifier.installedMap(context)["versionCode"] as Long)) { "更新版本或包名无效" }
        require(next.getString("candidateId") == "${next.getLong("releaseId")}:${next.getLong("versionCode")}:$hash") { "更新身份无效" }
        require(tag == "v${next.getString("versionName")}" && next.getInt("minSdk") in 26..Build.VERSION.SDK_INT) { "更新不兼容当前系统" }
        val abis = asset.getJSONArray("abis")
        require((0 until abis.length()).any { abis.getString(it) in Build.SUPPORTED_ABIS }) { "安装包不兼容当前设备" }
        val current = read()
        if (current != null && current.optString("phase") !in listOf("failed", "cancelled", "idle")) {
            require(current.optString("candidateId") == next.getString("candidateId")) { "请先取消当前更新下载" }
            return@synchronized
        }
        current?.let { removeOwned(it) }
        next.put("phase", "queued").put("bytes", 0)
        save(next) // Crash recovery can adopt an enqueued system task by exact destination.
        val target = destination(next)
        if (target.exists()) check(target.delete())
        try {
            val request = DownloadManager.Request(uri).setTitle("XDownloader ${next.getString("versionName")}")
                .setMimeType("application/vnd.android.package-archive").setDestinationUri(Uri.fromFile(target))
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            next.put("downloadId", manager.enqueue(request)); save(next)
        } catch (e: Exception) { next.put("phase", "failed").put("error", "无法开始更新下载，请重试"); save(next); throw e }
    }
    private fun removeOwned(state: JSONObject) {
        recoverId(state)?.let { manager.remove(it) }
        val file = destination(state)
        if (file.exists()) check(file.delete()) { "无法移除更新缓存" }
    }
    fun cancel(candidateId: String) = synchronized(lock) {
        val state = read() ?: return@synchronized
        require(state.getString("candidateId") == candidateId) { "更新任务已变化" }
        removeOwned(state); state.remove("downloadId"); state.put("phase", "cancelled"); state.remove("error"); save(state)
    }
    private fun markReady(state: JSONObject) {
        val file = destination(state)
        if (state.optLong("verifiedModified", -1) != file.lastModified() || !file.isFile ||
            file.length() != state.getJSONObject("asset").getLong("bytes")) {
            UpdatePackageVerifier.verify(context, file, state)
            state.put("verifiedModified", file.lastModified())
        }
        state.put("phase", if (state.optString("phase") == "permissionRequired" && !context.packageManager.canRequestPackageInstalls()) "permissionRequired" else "ready")
        state.remove("error")
    }
    fun snapshot(): Map<String, Any?> = synchronized(lock) {
        val state = read() ?: return@synchronized mapOf("phase" to "idle", "bytes" to 0L)
        if (state.getLong("versionCode") <= (UpdatePackageVerifier.installedMap(context)["versionCode"] as Long)) {
            removeOwned(state)
            File(context.cacheDir, "xdl-install/${state.getJSONObject("asset").getString("sha256")}.apk").delete()
            stateFile.delete(); return@synchronized mapOf("phase" to "idle", "bytes" to 0L)
        }
        if (state.optString("phase") in listOf("ready", "permissionRequired")) {
            // A validated file remains installable after Android prunes its transfer row.
            try { markReady(state) }
            catch (e: Exception) { state.put("phase", "failed").put("error", e.message ?: "安装包验证失败") }
            save(state)
        } else if (state.optString("phase") !in listOf("failed", "cancelled")) {
            val id = recoverId(state)
            if (id == null) {
                state.put("phase", "failed").put("error", "系统更新任务已丢失，请重新下载")
            } else manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
                if (!cursor.moveToFirst()) state.put("phase", "failed").put("error", "系统更新任务已丢失，请重新下载")
                else {
                    val bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    state.put("bytes", bytes)
                    if (bytes > state.getJSONObject("asset").getLong("bytes")) {
                        removeOwned(state); state.put("phase", "failed").put("error", "安装包超过预期大小，请重新下载")
                    } else when (status) {
                        DownloadManager.STATUS_SUCCESSFUL -> {
                            try {
                                markReady(state)
                            } catch (e: Exception) { state.put("phase", "failed").put("error", e.message ?: "安装包验证失败") }
                        }
                        DownloadManager.STATUS_FAILED -> state.put("phase", "failed").put("error", "更新下载失败，请重新下载")
                        DownloadManager.STATUS_RUNNING -> state.put("phase", "running")
                        else -> state.put("phase", "queued")
                    }
                }
            }
            save(state)
        }
        mapOf("candidateId" to state.getString("candidateId"), "phase" to state.getString("phase"),
            "versionName" to state.getString("versionName"), "versionCode" to state.getLong("versionCode"),
            "bytes" to state.optLong("bytes"), "totalBytes" to state.getJSONObject("asset").getLong("bytes"),
            "error" to if (state.has("error")) state.getString("error") else null)
    }
    fun verifiedFile(candidateId: String): File = synchronized(lock) {
        val state = read() ?: throw IllegalArgumentException("没有可安装的更新")
        require(state.getString("candidateId") == candidateId && state.getString("phase") in listOf("ready", "permissionRequired")) { "更新尚未下载完成或任务已变化" }
        // The installer receives an internal private copy, also on API 26–28.
        // External app directories there may be readable by other storage apps.
        val folder = File(context.cacheDir, "xdl-install").apply { check(mkdirs() || isDirectory) }
        val file = File(folder, "${state.getJSONObject("asset").getString("sha256")}.apk")
        val temporary = File(folder, file.name + ".tmp")
        try {
            val expectedBytes = state.getJSONObject("asset").getLong("bytes")
            require(destination(state).length() == expectedBytes) { "安装包大小已变化，请重新下载" }
            destination(state).inputStream().buffered().use { input -> temporary.outputStream().use { output ->
                val buffer = ByteArray(64 * 1024)
                var copied = 0L
                while (true) {
                    val count = input.read(buffer); if (count < 0) break
                    copied += count
                    require(copied <= expectedBytes) { "安装包大小已变化，请重新下载" }
                    output.write(buffer, 0, count)
                }
            } }
            UpdatePackageVerifier.verify(context, temporary, state)
            if (file.exists()) check(file.delete())
            check(temporary.renameTo(file)) { "无法准备安装包" }
            file
        } finally { if (temporary.exists()) temporary.delete() }
    }
    fun permissionRequired(candidateId: String) = synchronized(lock) {
        val state = read() ?: throw IllegalArgumentException("更新任务不存在")
        require(state.getString("candidateId") == candidateId)
        state.put("phase", "permissionRequired"); save(state)
    }
}

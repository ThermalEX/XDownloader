package com.xdl.app

import android.content.Context
import android.content.ContentUris
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File

object LegacyDataGateway {
    fun read(context: Context): Map<String, Any?> = mapOf(
        "sources" to context.getSharedPreferences("xdl_sources", Context.MODE_PRIVATE).all,
        "settings" to context.getSharedPreferences("xdl_settings", Context.MODE_PRIVATE).all,
        "historyJson" to context.getSharedPreferences("xdl_history", Context.MODE_PRIVATE).getString("items", null)
    )
    fun locate(context: Context, name: String): Map<String, Any?>? {
        if (name.isBlank() || name.contains('/') || name.contains('\\') || name in listOf(".", "..")) return null
        if (Build.VERSION.SDK_INT >= 29) {
            context.contentResolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.MIME_TYPE),
                "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
                arrayOf(name, "Download/XDownloader/%"), null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val uri = ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cursor.getLong(0))
                    val bytes = cursor.getLong(1)
                    try {
                        context.contentResolver.openFileDescriptor(uri, "r")?.use {
                            if (bytes > 0) return saved(uri, name, bytes, cursor.getString(2) ?: "video/mp4")
                        }
                    } catch (_: java.io.FileNotFoundException) { }
                    catch (_: SecurityException) { }
                }
            }
            return null
        }
        val file = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "XDownloader/$name")
        if (!file.isFile || !file.canRead() || file.length() <= 0) return null
        return saved(FileProvider.getUriForFile(context, "${context.packageName}.files", file), name, file.length(), "video/mp4")
    }
    private fun saved(uri: Uri, name: String, bytes: Long, mime: String): Map<String, Any?> =
        mapOf("locator" to uri.toString(), "displayName" to name, "bytes" to bytes, "mimeType" to mime)
}

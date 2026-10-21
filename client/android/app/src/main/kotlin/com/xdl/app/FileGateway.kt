package com.xdl.app

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.IOException

object FileGateway {
    fun open(context: Context, locator: String, mime: String) {
        val uri = Uri.parse(locator)
        ensureReadable(context, locator)
        context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }
    fun ensureReadable(context: Context, locator: String) {
        val uri = Uri.parse(locator)
        try { context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { } ?: throw FileNotFoundException(locator) }
        catch (_: SecurityException) { throw FileNotFoundException("File is no longer accessible") }
    }
    fun thumbnail(context: Context, locator: String): ByteArray? {
        ensureReadable(context, locator)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, Uri.parse(locator))
            val frame = if (Build.VERSION.SDK_INT >= 27) retriever.getScaledFrameAtTime(-1L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 320, 320)
                else retriever.getFrameAtTime(-1L)
            if (frame == null) return null
            var scaled = frame
            try {
                val longest = maxOf(frame.width, frame.height)
                if (longest > 320) scaled = Bitmap.createScaledBitmap(frame, maxOf(1, frame.width * 320 / longest), maxOf(1, frame.height * 320 / longest), true)
                val output = ByteArrayOutputStream()
                return if (scaled.compress(Bitmap.CompressFormat.JPEG, 75, output)) output.toByteArray() else null
            } finally {
                if (scaled !== frame) scaled.recycle()
                frame.recycle()
            }
        } finally { retriever.release() }
    }
    fun openDirectory(context: Context) {
        context.startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
    fun deleteSavedFile(context: Context, locator: String) {
        val uri = Uri.parse(locator)
        val path = uri.pathSegments
        val downloadsRow = uri.authority == "media" && path.size == 3 &&
            path[0] in listOf("external", "external_primary") && path[1] == "downloads" && path[2].toLongOrNull() != null
        val ownProvider = uri.authority == "${context.packageName}.files" && path.firstOrNull() == "downloads"
        require(uri.scheme == "content" && (downloadsRow || ownProvider)) { "Unsupported download locator" }
        try {
            if (context.contentResolver.delete(uri, null, null) == 0) {
                // Missing files are already deleted; a still-readable file means deletion failed.
                context.contentResolver.openAssetFileDescriptor(uri, "r")?.use {
                    throw IOException("The download could not be deleted")
                }
            }
        } catch (_: FileNotFoundException) { }
    }
}

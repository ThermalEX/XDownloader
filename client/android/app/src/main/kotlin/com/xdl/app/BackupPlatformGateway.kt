package com.xdl.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.IOException
import java.security.KeyStore
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Activity-scoped SAF requests; no filesystem permission or persistent URI grant. */
internal class BackupPlatformGateway(private val activity: Activity) {
    private val context = activity.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val calls = mutableSetOf<PendingCall>()
    private var document: PendingCall? = null
    private var destroyed = false

    private class PendingCall(
        val result: MethodChannel.Result,
        val method: String,
        val bytes: ByteArray? = null
    ) {
        val cancelled = AtomicBoolean(false)
        var completed = false // Accessed only on the Activity main thread.
        var requestCode = -1
        var pickerOutstanding = false
        private var stream: Closeable? = null

        fun checkActive() {
            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                throw CancellationException()
            }
        }

        @Synchronized fun attach(value: Closeable) {
            if (cancelled.get()) {
                value.close()
                throw CancellationException()
            }
            stream = value
        }

        @Synchronized fun detach() { stream = null }

        fun closeStream() {
            val value = synchronized(this) { stream.also { stream = null } }
            try { value?.close() } catch (_: Exception) { }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method !in METHODS) return false
        if (call.method == "backupCancel") {
            cancelDocument()
            result.success(null)
            return true
        }
        if (destroyed) {
            result.error("backupCancelled", "Backup operation cancelled", null)
            return true
        }
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val credentialSlot = if (args.containsKey("key")) args["key"] as? String else "default"
        if ((call.method == "backupReadPassword" || call.method == "backupWritePassword") &&
            (credentialSlot == null || !credentialSlot.matches(Regex("^[A-Za-z0-9_-]{1,128}$")))) {
            result.error("backupArguments", "Invalid protected credential slot", null)
            return true
        }
        when (call.method) {
            "backupReadPassword" -> {
                val pending = register(result, call.method)
                run(pending) { readPassword(credentialSlot!!) }
            }
            "backupWritePassword" -> {
                val password = args["password"] as? String
                if (password == null) {
                    result.error("backupArguments", "Invalid credential arguments", null)
                    return true
                }
                val pending = register(result, call.method)
                run(pending) { writePassword(password, credentialSlot!!); null }
            }
            "backupImport", "backupExport" -> {
                if (document != null) {
                    result.error("backupBusy", "A backup document operation is already open", null)
                    return true
                }
                val export = call.method == "backupExport"
                val name = args["name"] as? String
                val bytes = args["bytes"] as? ByteArray
                if (export && (name == null || !validName(name) || bytes == null || bytes.size > MAX_BYTES)) {
                    result.error("backupArguments", "Invalid backup document arguments", null)
                    return true
                }
                val pending = register(result, call.method, bytes)
                document = pending
                pending.requestCode = NEXT_REQUEST.getAndUpdate {
                    if (it == LAST_REQUEST) FIRST_REQUEST else it + 1
                }
                pending.pickerOutstanding = true
                val intent = Intent(if (export) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(if (export) "application/zip" else "*/*")
                if (export) intent.putExtra(Intent.EXTRA_TITLE, name)
                try {
                    activity.startActivityForResult(intent, pending.requestCode)
                } catch (_: Exception) {
                    pending.pickerOutstanding = false
                    fail(pending)
                }
            }
        }
        return true
    }

    private fun register(result: MethodChannel.Result, method: String, bytes: ByteArray? = null): PendingCall {
        val pending = PendingCall(result, method, bytes)
        calls.add(pending)
        return pending
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val pending = document ?: return false
        if (requestCode != pending.requestCode) return false
        if (!pending.pickerOutstanding) return true
        pending.pickerOutstanding = false
        if (pending.completed) {
            // A cancelled picker keeps its slot until this result. Never reuse it
            // for another request or perform IO using its late URI.
            document = null
            return true
        }
        if (resultCode != Activity.RESULT_OK) {
            finish(pending, if (pending.method == "backupImport") null else false)
            return true
        }
        val uri = data?.data
        if (uri == null || uri.scheme != "content") {
            fail(pending)
            return true
        }
        run(pending) {
            if (pending.method == "backupImport") readDocument(pending, uri)
            else { writeDocument(pending, uri); true }
        }
        return true
    }

    private fun run(pending: PendingCall, operation: () -> Any?) {
        executor.execute {
            try {
                pending.checkActive()
                val value = operation()
                pending.checkActive()
                main.post { finish(pending, value) }
            } catch (_: Exception) {
                // Provider errors and crypto exceptions may contain private data or URIs.
                main.post { fail(pending) }
            }
        }
    }

    private fun finish(pending: PendingCall, value: Any?) {
        if (pending.completed) return
        pending.completed = true
        calls.remove(pending)
        if (document === pending && !pending.pickerOutstanding) document = null
        pending.result.success(value)
    }

    private fun fail(pending: PendingCall) {
        if (pending.completed) return
        pending.completed = true
        calls.remove(pending)
        if (document === pending) document = null
        val credential = pending.method == "backupReadPassword" || pending.method == "backupWritePassword"
        pending.result.error(
            if (credential) "backupCredentials" else "backupDocument",
            if (credential) "Unable to access protected WebDAV credentials" else "Unable to exchange backup document",
            null
        )
    }

    private fun readDocument(pending: PendingCall, uri: Uri): ByteArray {
        pending.checkActive()
        val input = context.contentResolver.openInputStream(uri) ?: throw IOException()
        input.use {
            pending.attach(it)
            try {
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    pending.checkActive()
                    val count = it.read(buffer)
                    if (count < 0) break
                    if (output.size() > MAX_BYTES - count) throw IOException()
                    output.write(buffer, 0, count)
                }
                pending.checkActive()
                return output.toByteArray()
            } finally { pending.detach() }
        }
    }

    private fun writeDocument(pending: PendingCall, uri: Uri) {
        val bytes = pending.bytes ?: throw IOException()
        pending.checkActive()
        val output = context.contentResolver.openOutputStream(uri, "wt") ?: throw IOException()
        output.use {
            pending.attach(it)
            try {
                var offset = 0
                while (offset < bytes.size) {
                    pending.checkActive()
                    val count = minOf(8192, bytes.size - offset)
                    it.write(bytes, offset, count)
                    offset += count
                }
                pending.checkActive()
                it.flush()
            } finally { pending.detach() }
        }
    }

    private fun key(): SecretKey {
        val alias = "${context.packageName}.webdav-password.v1"
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(alias, null)
        if (existing != null) return existing as SecretKey
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build())
        }.generateKey()
    }

    private fun credentialPreference(slot: String): String =
        if (slot == "default") "credential" else "credential_$slot"

    private fun credentialAad(slot: String): ByteArray =
        (if (slot == "default") context.packageName else "${context.packageName}:$slot")
            .toByteArray(Charsets.UTF_8)

    private fun writePassword(password: String, slot: String) {
        val prefs = context.getSharedPreferences("xdl_backup_secrets", Context.MODE_PRIVATE)
        val preference = credentialPreference(slot)
        if (password.isEmpty()) {
            if (!prefs.edit().remove(preference).commit()) throw IOException()
            return
        }
        val plain = password.toByteArray(Charsets.UTF_8)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            cipher.updateAAD(credentialAad(slot))
            val encrypted = cipher.doFinal(plain)
            val stored = "${Base64.encodeToString(cipher.iv, Base64.NO_WRAP)}:${Base64.encodeToString(encrypted, Base64.NO_WRAP)}"
            if (!prefs.edit().putString(preference, stored).commit()) throw IOException()
        } finally { plain.fill(0) }
    }

    private fun readPassword(slot: String): String {
        val stored = context.getSharedPreferences("xdl_backup_secrets", Context.MODE_PRIVATE)
            .getString(credentialPreference(slot), null) ?: return ""
        val parts = stored.split(':')
        if (parts.size != 2) throw IOException()
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val encrypted = Base64.decode(parts[1], Base64.NO_WRAP)
        if (iv.size != 12 || encrypted.size < 16) throw IOException()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        cipher.updateAAD(credentialAad(slot))
        val plain = cipher.doFinal(encrypted)
        return try { String(plain, Charsets.UTF_8) } finally { plain.fill(0) }
    }

    private fun cancelDocument() {
        val pending = document ?: return
        if (pending.completed) return
        pending.cancelled.set(true)
        finish(pending, if (pending.method == "backupImport") null else false)
        if (pending.pickerOutstanding) {
            // Best effort close; retain the tombstone if a provider returns late.
            try { activity.finishActivity(pending.requestCode) } catch (_: Exception) { }
        }
        Thread({ pending.closeStream() }, "xdl-backup-close").start()
    }

    fun onDestroy() {
        destroyed = true
        val pending = calls.toList()
        pending.forEach {
            it.cancelled.set(true)
            when (it.method) {
                "backupImport" -> finish(it, null)
                "backupExport" -> finish(it, false)
                else -> {
                    it.completed = true
                    calls.remove(it)
                    it.result.error("backupCancelled", "Backup operation cancelled", null)
                }
            }
        }
        executor.shutdownNow()
        document = null
        // Some document providers block in read/write; closing must not block onDestroy.
        if (pending.isNotEmpty()) Thread({ pending.forEach { it.closeStream() } }, "xdl-backup-close").start()
    }

    companion object {
        private const val MAX_BYTES = 16 * 1024 * 1024
        private const val FIRST_REQUEST = 0x6000
        private const val LAST_REQUEST = 0x7fff
        // Process-wide generation also separates recreated Activities from old results.
        private val NEXT_REQUEST = AtomicInteger(FIRST_REQUEST)
        private val METHODS = setOf("backupReadPassword", "backupWritePassword", "backupImport", "backupExport", "backupCancel")

        private fun validName(name: String): Boolean =
            name.isNotBlank() && name != "." && name != ".." &&
                name.toByteArray(Charsets.UTF_8).size <= 255 &&
                name.none { it <= '\u001f' || it == '\u007f' || it in "<>:\"/\\|?*" }
    }
}

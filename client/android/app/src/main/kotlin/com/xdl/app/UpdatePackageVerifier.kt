package com.xdl.app

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject

/** The installed signing identity, not a downloaded manifest, is the trust root. */
object UpdatePackageVerifier {
    private val flags: Int get() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    @Suppress("DEPRECATION")
    private fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    @Suppress("DEPRECATION")
    private fun certificates(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { sig -> MessageDigest.getInstance("SHA-256").digest(sig.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 255) } }?.toSet() ?: emptySet()
    }
    @Suppress("DEPRECATION")
    fun installed(context: Context): PackageInfo = context.packageManager.getPackageInfo(context.packageName, flags)
    fun installedMap(context: Context): Map<String, Any> {
        val info = installed(context)
        return mapOf("packageName" to context.packageName, "versionName" to (info.versionName ?: ""),
            "versionCode" to code(info), "sdkInt" to Build.VERSION.SDK_INT, "supportedAbis" to Build.SUPPORTED_ABIS.toList())
    }
    @Suppress("DEPRECATION")
    fun verify(context: Context, file: File, expected: JSONObject) {
        val asset = expected.getJSONObject("asset")
        val length = asset.getLong("bytes")
        require(length in 1..(200L * 1024 * 1024) && file.isFile && file.length() == length) { "安装包大小不符，请重新下载" }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        val actualHash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
        require(actualHash == asset.getString("sha256")) { "安装包校验失败，请重新下载" }
        val archive = context.packageManager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: throw IllegalArgumentException("无法读取安装包")
        val current = installed(context)
        require(archive.packageName == context.packageName && expected.getString("packageName") == context.packageName) { "安装包不属于本应用" }
        require(code(archive) == expected.getLong("versionCode") && code(archive) > code(current)) { "安装包版本不符或无需升级" }
        require(archive.versionName == expected.getString("versionName")) { "安装包版本名称不符" }
        require(archive.applicationInfo?.minSdkVersion == expected.getInt("minSdk") && expected.getInt("minSdk") <= Build.VERSION.SDK_INT) { "安装包不兼容当前系统" }
        val trusted = certificates(current)
        require(trusted.size == 1 && certificates(archive) == trusted) { "安装包签名与当前应用不一致，已拒绝安装" }
    }
}

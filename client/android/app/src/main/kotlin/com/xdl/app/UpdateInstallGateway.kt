package com.xdl.app

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import java.io.File

/** Activity launches run on the main thread; verification runs before this gateway. */
object UpdateInstallGateway {
    fun install(activity: MainActivity, file: File): String {
        // Verification/copying may outlast the foreground request from Dart.
        if (!activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return "deferred"
        if (!activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
            return "permissionRequired"
        }
        activity.startActivity(installerIntent(activity, file))
        return "installer"
    }
    fun installerIntent(activity: MainActivity, file: File): Intent {
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", file)
        return Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    fun openPage(activity: MainActivity, value: String) {
        val uri = Uri.parse(value)
        require(uri.scheme == "https" && uri.host == "github.com" && uri.userInfo == null && uri.port == -1 && uri.query == null && uri.fragment == null &&
            (uri.path == "/ThermalEX/XDownloader" || uri.path == "/ThermalEX/XDownloader/releases" || uri.path?.startsWith("/ThermalEX/XDownloader/releases/tag/") == true)) { "发布地址无效" }
        activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
    }
}

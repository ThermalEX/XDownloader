package com.xdl.app
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
object ProbeGateway {
    fun handle(activity: MainActivity, store: NativeDownloads, call: MethodCall, result: MethodChannel.Result): Boolean = false
}

package com.xdl.app

import android.content.Intent
import io.flutter.plugin.common.EventChannel
import java.util.ArrayDeque

/** Retain arrivals between initialText and attaching the hot-event subscription. */
class NativeShareGateway : EventChannel.StreamHandler {
    private val pending = ArrayDeque<Pair<Intent, String>>()
    private var sink: EventChannel.EventSink? = null
    @Synchronized fun accept(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND || intent.type?.startsWith("text/") != true) return
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
        if (text.isNullOrEmpty()) return
        val entry = intent to text
        if (sink == null) pending.addLast(entry) else deliver(entry)
    }
    private fun deliver(entry: Pair<Intent, String>) {
        sink?.success(entry.second)
        entry.first.removeExtra(Intent.EXTRA_TEXT)
    }
    @Synchronized fun initialText(): String? {
        val entry = pending.pollFirst() ?: return null
        entry.first.removeExtra(Intent.EXTRA_TEXT)
        return entry.second
    }
    @Synchronized override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        while (sink != null && pending.isNotEmpty()) deliver(pending.removeFirst())
    }
    @Synchronized override fun onCancel(arguments: Any?) { sink = null }
}

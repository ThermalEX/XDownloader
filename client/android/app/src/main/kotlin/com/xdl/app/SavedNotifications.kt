package com.xdl.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

object SavedNotifications {
    fun show(context: Context, taskId: String, name: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        manager.createNotificationChannel(NotificationChannel("saved_downloads", "下载完成", NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(context, MainActivity::class.java).putExtra("tab", "downloads")
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(context, taskId.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(taskId, 1, Notification.Builder(context, "saved_downloads")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("视频已保存").setContentText(name).setContentIntent(pending)
            .setAutoCancel(true).setOnlyAlertOnce(true).build())
    }
}

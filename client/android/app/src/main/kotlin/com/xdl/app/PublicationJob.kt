package com.xdl.app

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.app.DownloadManager
import android.os.PersistableBundle
import java.util.concurrent.Executors

class PublicationJob : JobService() {
    companion object {
        val executor = Executors.newSingleThreadExecutor()
        fun schedule(context: Context, taskId: String, jobId: Int) {
            val extras = PersistableBundle().apply { putString("taskId", taskId) }
            val job = JobInfo.Builder(jobId, ComponentName(context, PublicationJob::class.java))
                .setExtras(extras).setMinimumLatency(0).setPersisted(true).build()
            check(context.getSystemService(JobScheduler::class.java).schedule(job) == JobScheduler.RESULT_SUCCESS)
        }
    }
    override fun onStartJob(params: JobParameters): Boolean {
        executor.execute {
            try { NativeDownloads(applicationContext).process(params.extras.getString("taskId")!!) }
            catch (e: Exception) { android.util.Log.e("XDownloader", "Publication reconciliation failed", e) }
            finally { jobFinished(params, false) }
        }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean = true
}

class DownloadCompleteReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val pending = goAsync()
        PublicationJob.executor.execute {
            try { NativeDownloads(context).complete(intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)) }
            catch (e: Exception) { android.util.Log.e("XDownloader", "Cannot schedule publication; retry on next launch", e) }
            finally { pending.finish() }
        }
    }
}

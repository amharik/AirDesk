package com.airdesk.android.remote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.airdesk.android.MainActivity
import com.airdesk.android.R

class AndroidSSHService : Service() {
    private val binder = LocalBinder()
    private lateinit var serviceController: RemoteSSHServiceController
    private val notificationListener: (RemoteSSHServiceSnapshot) -> Unit = { snapshot ->
        if (startedForeground) {
            notificationManager.notify(NOTIFICATION_ID, buildNotification(snapshot.status))
        }
    }

    private val notificationManager: NotificationManager
        get() = getSystemService(NotificationManager::class.java)

    private var startedForeground = false

    override fun onCreate() {
        super.onCreate()
        val terminal = RemoteSSHTerminal(
            driver = RemoteSSHController(JschRemoteSSHTransport()),
            leases = RemoteSSHLeaseRegistry(),
        )
        serviceController = RemoteSSHServiceController(terminal)
        serviceController.addListener(notificationListener)
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            serviceController.stop()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        startForegroundCompat(buildNotification(serviceController.snapshot().status))
        return START_STICKY
    }

    override fun onDestroy() {
        serviceController.removeListener(notificationListener)
        serviceController.shutdown()
        startedForeground = false
        super.onDestroy()
    }

    private fun startForegroundCompat(notification: Notification) {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        startedForeground = true
    }

    private fun stopForegroundCompat() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        startedForeground = false
    }

    private fun buildNotification(status: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_airdesk)
            .setContentTitle("AirDesk remote terminal")
            .setContentText(status)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Remote terminal",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps the AirDesk SSH terminal connected while the app is in the background."
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
    }

    inner class LocalBinder : Binder() {
        fun controller(): RemoteSSHServiceController = serviceController
    }

    companion object {
        const val ACTION_START = "com.airdesk.android.remote.action.START"
        const val ACTION_STOP = "com.airdesk.android.remote.action.STOP"
        const val NOTIFICATION_CHANNEL_ID = "airdesk_remote_terminal"
        const val NOTIFICATION_ID = 2_009

        fun start(context: Context) {
            val intent = Intent(context, AndroidSSHService::class.java).apply {
                action = ACTION_START
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, AndroidSSHService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}

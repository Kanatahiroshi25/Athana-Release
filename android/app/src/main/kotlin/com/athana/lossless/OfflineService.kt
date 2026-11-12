package com.athana.lossless

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.StatFs
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest

/**
 * Offline copies of songs that live in a cloud app such as Google Drive.
 * Each song is copied once into Athana's own storage. Playing uses the copy from then on, so it needs no internet.
 */
object OfflineStore {
    private var index: HashMap<String, File>? = null

    fun dir(ctx: Context): File = File(ctx.filesDir, "offline").apply { mkdirs() }

    fun key(uri: String): String =
        MessageDigest.getInstance("SHA-1").digest(uri.toByteArray()).joinToString("") { "%02x".format(it) }

    @Synchronized
    private fun idx(ctx: Context): HashMap<String, File> {
        index?.let { return it }
        val m = HashMap<String, File>()
        dir(ctx).listFiles()?.forEach { f -> if (!f.name.endsWith(".part")) m[f.name.substringBefore('.')] = f }
        index = m
        return m
    }

    /** The finished copy of this song, or null when it has not been saved yet. */
    @Synchronized
    fun find(ctx: Context, uri: String): File? = idx(ctx)[key(uri)]?.takeIf { it.exists() && it.length() > 0 }

    @Synchronized
    fun add(ctx: Context, uri: String, f: File) { idx(ctx)[key(uri)] = f }

    /** A song got a new link (it was picked again): its saved copy moves over to the new link, so it is not downloaded twice. */
    @Synchronized
    fun rekey(ctx: Context, oldUri: String, newUri: String) {
        val f = find(ctx, oldUri) ?: return
        val dest = File(dir(ctx), key(newUri) + "." + f.name.substringAfter('.', "bin"))
        if (dest.exists()) return
        if (f.renameTo(dest)) {
            idx(ctx).remove(key(oldUri))
            idx(ctx)[key(newUri)] = dest
        }
    }

    @Synchronized
    fun count(ctx: Context): Int = idx(ctx).values.count { it.exists() }

    fun bytes(ctx: Context): Long = dir(ctx).listFiles()?.sumOf { it.length() } ?: 0L

    @Synchronized
    fun clear(ctx: Context) {
        dir(ctx).listFiles()?.forEach { it.delete() }
        index = HashMap()
    }

    /** The song that is playing right now. Its copy is never removed. */
    @Volatile var playingKey: String = ""

    /** Keeps the saved songs within [limit] bytes by removing the ones played longest ago. 0 means no limit. */
    @Synchronized
    fun trim(ctx: Context, limit: Long) {
        if (limit <= 0) return
        val files = (dir(ctx).listFiles() ?: return).filter { !it.name.endsWith(".part") }.sortedBy { it.lastModified() }
        var total = files.sumOf { it.length() }
        for (f in files) {
            if (total <= limit) break
            if (playingKey.isNotEmpty() && f.name.startsWith(playingKey)) continue
            total -= f.length()
            if (f.delete()) idx(ctx).remove(f.name.substringBefore('.'))
        }
    }

    fun extOf(name: String): String =
        name.substringAfterLast('.', "bin").lowercase().filter { it.isLetterOrDigit() }.take(5).ifEmpty { "bin" }
}

/** Thrown when the phone has too little free space to save a song. */
class OfflineNoSpace : IOException("no space")

class OfflineService : Service() {
    companion object {
        private const val CH = "athana_offline"
        private const val NOTE = 4412
        private const val RESERVE = 1024L * 1024 * 1024        // always leave 1 GB free on the phone
        private const val BUDGET_MS = 5.5 * 60 * 60 * 1000       // Android lets a background download run about 6 hours a day
        private const val SPEED = 3L * 1024 * 1024               // about 3 MB per second at most, so playback and other apps stay smooth

        private val lock = Any()
        private val queue = ArrayDeque<Array<String>>()
        private val queued = HashSet<String>()
        private val tries = HashMap<String, Int>()

        @Volatile var running = false
        @Volatile var paused = false
        @Volatile var limitBytes = 0L
        @Volatile var wifiOnly = true
        @Volatile var stopNow = false
        @Volatile var waiting = ""
        @Volatile var listener: ((Map<String, Any?>) -> Unit)? = null
        @Volatile private var sessionTotal = 0
        @Volatile private var sessionDone = 0

        /** Adds songs to the list and starts the background service. Songs that are already saved are skipped. */
        private fun prefs(ctx: Context) = ctx.getSharedPreferences("athana_native", Context.MODE_PRIVATE)

        fun networkOk(ctx: Context, wifi: Boolean): Boolean {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.activeNetwork?.let { cm.getNetworkCapabilities(it) }
            val online = caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            return online && (!wifi || !cm.isActiveNetworkMetered)
        }

        /**
         * Adds songs to the list and starts the background service. Songs that are already saved are skipped.
         * [force] is true when the person asked for it (it also clears an earlier Pause). [limit] is the size limit in bytes, 0 for none.
         */
        fun start(ctx: Context, items: List<Array<String>>, wifi: Boolean, force: Boolean, limit: Long) {
            wifiOnly = wifi
            limitBytes = limit
            if (force) { paused = false; prefs(ctx).edit().putBoolean("offPaused", false).apply() }
            else paused = prefs(ctx).getBoolean("offPaused", false)
            synchronized(lock) {
                for (item in items) {
                    if (OfflineStore.find(ctx, item[0]) != null) continue
                    if (queued.add(item[0])) { queue.addLast(item); if (running) sessionTotal++ }
                }
                if (queue.isEmpty()) { emit(ctx); return }
            }
            if (running || paused) { emit(ctx); return }
            if (!networkOk(ctx, wifi)) {
                // Nothing to do right now. The songs stay in the list and start when Athana is opened on Wi-Fi again.
                waiting = if (wifi) "Waiting for Wi-Fi" else "Waiting for a connection"
                emit(ctx)
                return
            }
            waiting = ""
            stopNow = false
            val i = Intent(ctx, OfflineService::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        /** The person pressed Pause. The list is kept, and nothing starts again until they ask. */
        fun pause(ctx: Context) {
            stopNow = true
            paused = true
            prefs(ctx).edit().putBoolean("offPaused", true).apply()
            emit(ctx)
        }

        /** Forgets the songs that are waiting (for example when the mode changes). */
        fun clearQueue() {
            stopNow = true
            synchronized(lock) { queue.clear(); queued.clear() }
        }

        fun stop() { stopNow = true }

        /**
         * Copies one song into Athana's storage, reading it from start to end. Returns false when it was stopped half way.
         * [background] copies are slow, gentle and can be paused. A foreground copy (a song that could not be streamed) runs at full speed.
         */
        fun copyOne(ctx: Context, uri: String, name: String, background: Boolean): Boolean {
            val dir = OfflineStore.dir(ctx)
            val key = OfflineStore.key(uri)
            val ext = OfflineStore.extOf(name)
            val part = File(dir, if (background) "$key.$ext.part" else "$key.$ext.fg.part")
            val fin = File(dir, "$key.$ext")
            val pfd = ctx.contentResolver.openFileDescriptor(Uri.parse(uri), "r") ?: return false
            pfd.use {
                val total = it.statSize
                FileInputStream(it.fileDescriptor).use { input ->
                    var have = if (part.exists()) part.length() else 0L
                    if (total > 0 && have >= total) have = 0L
                    if (have > 0) {
                        try { input.channel.position(have) } catch (_: Exception) { have = 0L }
                    }
                    val need = if (total > 0) total - have else 50L * 1024 * 1024
                    if (StatFs(ctx.filesDir.path).availableBytes - need < RESERVE) throw OfflineNoSpace()
                    FileOutputStream(part, have > 0).use { out ->
                        val buf = ByteArray(64 * 1024)
                        var written = 0L
                        val t0 = SystemClock.elapsedRealtime()
                        while (true) {
                            if (background && stopNow) { out.flush(); return false }
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            written += n
                            if (background) {
                                // gentle speed limit
                                val ahead = written * 1000 / SPEED - (SystemClock.elapsedRealtime() - t0)
                                if (ahead > 20) try { Thread.sleep(ahead) } catch (_: InterruptedException) { }
                            }
                        }
                    }
                }
                if (total > 0 && part.length() != total) throw IOException("incomplete")
            }
            if (part.length() == 0L) { part.delete(); return false }
            if (fin.exists()) fin.delete()
            if (!part.renameTo(fin)) throw IOException("rename failed")
            OfflineStore.add(ctx, uri, fin)
            OfflineStore.trim(ctx, limitBytes)
            return true
        }

        fun status(ctx: Context): Map<String, Any?> = mapOf(
            "type" to "off",
            "running" to running,
            "queued" to synchronized(lock) { queue.size },
            "done" to OfflineStore.count(ctx),
            "bytes" to OfflineStore.bytes(ctx),
            "wait" to waiting,
            "paused" to paused
        )

        fun emit(ctx: Context) { listener?.invoke(status(ctx)) }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            pause(applicationContext)
            if (!running) stopSelf()
            return START_NOT_STICKY
        }
        startInForeground("Getting ready", 0, 0)
        if (!running) {
            running = true
            stopNow = false
            sessionDone = 0
            synchronized(lock) { sessionTotal = queue.size }
            Thread { work() }.apply { name = "athana-offline"; start() }
        }
        return START_NOT_STICKY
    }

    // ------------------------------------------------------------------ the work
    private fun work() {
        val ctx = applicationContext
        val began = SystemClock.elapsedRealtime()
        val sp = getSharedPreferences("athana_native", MODE_PRIVATE)
        val now = System.currentTimeMillis()
        var window = sp.getLong("offWindow", 0L)
        var used = sp.getLong("offUsed", 0L)
        if (now - window > 24L * 60 * 60 * 1000) { window = now; used = 0L }
        val budget = (BUDGET_MS - used).toLong()
        try {
            if (budget <= 0) { waiting = "Daily time limit reached. It continues tomorrow."; return }
            waiting = ""
            while (!stopNow) {
                if (SystemClock.elapsedRealtime() - began > budget) { waiting = "Paused for now. It continues next time you open Athana."; break }
                if (synchronized(lock) { queue.isEmpty() }) break
                if (!waitForNetwork()) break
                val item = synchronized(lock) { queue.removeFirstOrNull()?.also { queued.remove(it[0]) } } ?: break
                if (OfflineStore.find(ctx, item[0]) != null) continue
                try {
                    note(item[1])
                    val ok = copyOne(ctx, item[0], item[1], true)
                    if (ok) {
                        sessionDone++
                        tries.remove(item[0])
                        OfflineStore.trim(ctx, limitBytes)
                        emit(ctx)
                    } else if (stopNow) {
                        synchronized(lock) { if (queued.add(item[0])) queue.addFirst(item) } // stopped half way: it carries on later
                    }
                } catch (e: SecurityException) {
                    // Android no longer lets Athana read this file. Skip it.
                } catch (e: OfflineNoSpace) {
                    waiting = "Not enough free space on the phone."
                    break
                } catch (e: IOException) {
                    // Connection dropped. Try this song again later, up to three times. The part already saved is kept.
                    val n = (tries[item[0]] ?: 0) + 1
                    tries[item[0]] = n
                    if (n < 3) synchronized(lock) { if (queued.add(item[0])) queue.addLast(item) }
                    try { Thread.sleep(15000) } catch (_: InterruptedException) { }
                } catch (e: Exception) {
                    android.util.Log.e("Athana", "offline copy failed", e)
                }
            }
        } finally {
            val ranFor = SystemClock.elapsedRealtime() - began
            sp.edit().putLong("offWindow", window).putLong("offUsed", used + ranFor).apply()
            running = false
            try { stopForeground(true) } catch (_: Exception) { }
            stopSelf()
            emit(ctx)
        }
    }

    private fun waitForNetwork(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val since = SystemClock.elapsedRealtime()
        while (!stopNow) {
            if (SystemClock.elapsedRealtime() - since > 3 * 60 * 1000) return false // the songs stay in the list for next time
            val net = cm.activeNetwork
            val caps = net?.let { cm.getNetworkCapabilities(it) }
            val online = caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            if (online && (!wifiOnly || !cm.isActiveNetworkMetered)) { waiting = ""; return true }
            waiting = if (!online) "Waiting for a connection" else "Waiting for Wi-Fi"
            note("")
            emit(applicationContext)
            try { Thread.sleep(20000) } catch (_: InterruptedException) { }
        }
        return false
    }

    // ------------------------------------------------------------------ notification
    private fun note(current: String) {
        val total = sessionTotal
        val done = sessionDone
        val text = if (waiting.isNotEmpty()) waiting else if (current.isNotEmpty()) current else "Saving songs"
        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTE, build("Saving songs for offline · $done of $total", text, total, done))
        } catch (_: Exception) { }
    }

    private fun startInForeground(title: String, total: Int, done: Int) {
        val n = build(title, "Songs from Google Drive are saved once, so they play without internet.", total, done)
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTE, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC) else startForeground(NOTE, n)
    }

    private fun build(title: String, text: String, total: Int, done: Int): android.app.Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CH) == null) {
                nm.createNotificationChannel(NotificationChannel(CH, "Offline copies", NotificationManager.IMPORTANCE_LOW))
            }
        }
        val stop = PendingIntent.getService(
            this, 1, Intent(this, OfflineService::class.java).setAction("stop"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val open = PendingIntent.getActivity(
            this, 2, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CH)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .setProgress(if (total > 0) total else 0, done.coerceAtMost(total), total <= 0)
            .addAction(0, "Pause", stop)
            .build()
    }
}

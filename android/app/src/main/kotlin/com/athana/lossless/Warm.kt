package com.athana.lossless

import android.content.Context
import android.net.Uri
import android.os.StatFs
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * "Warm up the next song": while a Google Drive song plays, the next one or two are copied into a temporary folder, so pressing
 * Next starts them at once. These copies are not saved songs. At most two exist, they are removed as soon as the queue moves on,
 * and anything left over is swept away the next time Athana starts. The phone always keeps 1 GB free.
 */
object Warm {
    private const val RESERVE = 1024L * 1024 * 1024        // always leave 1 GB free on the phone
    private const val MAX_SONG = 250L * 1024 * 1024        // a longer file is not warmed, it streams as usual

    private val lock = Any()
    private var wanted: List<Array<String>> = emptyList()   // [uri, name] of the songs to warm, in play order
    private var running = false
    private var wifiOnly = true
    private val failed = HashSet<String>()                  // songs that could not be copied this session, so they are not retried in a loop
    /** Set by the player (main thread): the song that plays now is a stream with little loaded. The copier then waits, so the music comes first. */
    @Volatile var streamLow = false
    @Volatile private var keep: Set<String> = emptySet()    // keys of the playing song and of the wanted songs

    private fun dir(ctx: Context): File = File(ctx.cacheDir, "warm").apply { mkdirs() }

    /** The finished temporary copy of this song, or null. */
    fun find(ctx: Context, uri: String): File? {
        val k = OfflineStore.key(uri)
        return dir(ctx).listFiles()?.firstOrNull { !it.name.endsWith(".part") && it.name.substringBefore('.') == k && it.length() > 0 }
    }

    /** Removes every finished copy that is not the playing song or a wanted one. */
    private fun prune(ctx: Context) {
        val k = keep
        dir(ctx).listFiles()?.forEach { f ->
            if (!f.name.endsWith(".part") && f.name.substringBefore('.') !in k && f.delete()) android.util.Log.i("Athana", "warm: removed a temporary copy")
        }
    }

    /** Called when Athana starts: copies left behind by an earlier run are removed (the song playing now, if any, stays). */
    fun sweep(ctx: Context) {
        val app = ctx.applicationContext
        synchronized(lock) {
            if (OfflineStore.playingKey.isNotEmpty() && OfflineStore.playingKey !in keep) keep = keep + OfflineStore.playingKey
            prune(app)
        }
    }

    /**
     * Sets which songs should be warm. [current] is the song that plays now (its copy, if it has one, stays). [items] are
     * [uri, name] pairs for the next songs; an empty list removes every temporary copy except the playing one.
     */
    fun request(ctx: Context, current: String, items: List<Array<String>>, wifi: Boolean) {
        val app = ctx.applicationContext
        var launch = false
        synchronized(lock) {
            wifiOnly = wifi
            wanted = items
            val k = HashSet<String>()
            if (current.isNotEmpty()) k.add(OfflineStore.key(current))
            for (w in items) k.add(OfflineStore.key(w[0]))
            keep = k
            prune(app)
            if (items.isNotEmpty() && !running) {
                running = true
                launch = true
            }
        }
        if (launch) Thread { work(app) }.apply { name = "athana-warm"; isDaemon = true; start() }
    }

    private fun work(ctx: Context) {
        try {
            while (true) {
                val item: Array<String>? = synchronized(lock) {
                    val next = wanted.firstOrNull {
                        OfflineStore.key(it[0]) !in failed && OfflineStore.find(ctx, it[0]) == null && find(ctx, it[0]) == null
                    }
                    if (next == null) running = false
                    next
                }
                if (item == null) return
                val ok = try {
                    copy(ctx, item[0], item[1])
                } catch (e: Throwable) {
                    android.util.Log.w("Athana", "warm copy failed: " + e.javaClass.simpleName)
                    false
                }
                if (!ok) {
                    android.util.Log.i("Athana", "warm: stopped or skipped " + item[1])
                    // Stopped (the queue moved on or Wi-Fi went away) or could not be copied: leave it to stream normally.
                    val key = OfflineStore.key(item[0])
                    val stillWanted = key in keep
                    synchronized(lock) { if (stillWanted) failed.add(key) }
                }
            }
        } catch (e: Throwable) {
            synchronized(lock) { running = false }
        }
    }

    private fun networkAllowed(ctx: Context): Boolean = OfflineService.networkOk(ctx, synchronized(lock) { wifiOnly })

    private fun copy(ctx: Context, uri: String, name: String): Boolean {
        if (!networkAllowed(ctx)) return false
        val key = OfflineStore.key(uri)
        val ext = OfflineStore.extOf(name)
        val dir = dir(ctx)
        val part = File(dir, "$key.$ext.part")
        val fin = File(dir, "$key.$ext")
        part.delete()
        var done = false
        try {
            val pfd = ctx.contentResolver.openFileDescriptor(Uri.parse(uri), "r") ?: return false
            pfd.use { d ->
                val total = d.statSize
                if (total > MAX_SONG) return false
                val need = if (total > 0) total else 50L * 1024 * 1024
                if (StatFs(ctx.cacheDir.path).availableBytes - need < RESERVE) return false
                FileInputStream(d.fileDescriptor).use { input ->
                    FileOutputStream(part).use { out ->
                        val buf = ByteArray(64 * 1024)
                        var chunks = 0
                        while (true) {
                            if (key !in keep) return false                            // the queue moved on: stop and throw the part away
                            if (chunks++ % 16 == 0 && !networkAllowed(ctx)) return false  // Wi-Fi went away
                            var waited = 0
                            while (streamLow && waited < 600 && key in keep) { Thread.sleep(250); waited++ }  // the music comes first
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                        }
                    }
                }
                if (total > 0 && part.length() != total) return false
            }
            if (part.length() == 0L) return false
            if (fin.exists()) fin.delete()
            done = part.renameTo(fin)
            if (done) android.util.Log.i("Athana", "warm: next song ready (" + (fin.length() / 1024 / 1024) + " MB) " + name)
            return done
        } finally {
            if (!done) part.delete()
        }
    }
}

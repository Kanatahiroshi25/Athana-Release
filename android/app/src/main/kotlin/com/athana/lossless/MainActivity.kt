package com.athana.lossless

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.charset.Charset
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Flutter draws the screens; this class is the bridge to Android: folder and file pickers, song details and covers,
 * and the Media3 ExoPlayer that really plays the music (shared with PlaybackService for the notification).
 * Channels: "athana/native" (calls from Dart) and "athana/events" (position, state, notification buttons back to Dart).
 */
class MainActivity : FlutterActivity() {

    private val ui = Handler(Looper.getMainLooper())
    private val scanner = Executors.newSingleThreadExecutor()
    private val worker = Executors.newSingleThreadExecutor()
    private val analyzer = Executors.newSingleThreadExecutor()
    @Volatile private var anTok = 0
    private val player: ExoPlayer by lazy { PlayerHolder.get(this) }
    private var controller: ListenableFuture<MediaController>? = null
    private var events: EventChannel.EventSink? = null
    private var pending: MethodChannel.Result? = null
    @Volatile private var tok = 0
    private val loud by lazy { LoudnessCache(applicationContext) }
    @Volatile private var normTarget = -18.0
    @Volatile private var curUri: Uri? = null
    @Volatile private var curName = ""
    private var lastLoad: Array<Any>? = null
    @Volatile private var recovering: String? = null
    private val recoverFailed = HashMap<String, Long>()
    @Volatile private var curAiff = false
    @Volatile private var curLoud: LoudnessResult? = null
    @Volatile private var measuring: String? = null

    private val audioRe = Regex(".*\\.(mp3|wav|wave|flac|m4a|aac|ogg|oga|opus|weba|wma|aiff?)$", RegexOption.IGNORE_CASE)
    private val imageRe = Regex(".*\\.(jpe?g|png|webp)$", RegexOption.IGNORE_CASE)
    private val coverRe = Regex("cover|folder|front|album|art|jacket|scan", RegexOption.IGNORE_CASE)

    private companion object {
        const val REQ_TREE = 7101
        const val REQ_FILES = 7102
        const val REQ_NOTIF = 7103
        const val REQ_IMAGE = 7104
        const val REQ_TEXT = 7105
        const val REQ_SAVE = 7106
        const val DRIVE_AUTH = "com.google.android.apps.docs.storage"
    }

    // ------------------------------------------------------------------ life cycle
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        player.addListener(listener)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
        try { (getSystemService(Context.AUDIO_SERVICE) as AudioManager).registerAudioDeviceCallback(outCallback, ui) } catch (_: Exception) { }
        registerReceiver(plugReceiver, android.content.IntentFilter(Intent.ACTION_HEADSET_PLUG))
        // Connecting a controller starts the background service that owns the notification.
        controller = MediaController.Builder(this, SessionToken(this, ComponentName(this, PlaybackService::class.java))).buildAsync()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        try { Warm.sweep(applicationContext) } catch (_: Exception) { }   // temporary next-song copies from an earlier run
        MethodChannel(messenger, "athana/native").setMethodCallHandler { call, result -> onCall(call, result) }
        EventChannel(messenger, "athana/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
                // Notification, lock screen and headset buttons go to Dart, which owns the queue, shuffle and repeat rules.
                PlayerHolder.remote = { name -> emit(mapOf("type" to "cmd", "name" to name)) }
                OfflineService.listener = { m -> emit(m) }
            }

            override fun onCancel(arguments: Any?) {
                events = null
                PlayerHolder.remote = null
                OfflineService.listener = null
            }
        })
    }

    /** Which output the sound goes to: speaker, wired headphones, a USB device or Bluetooth. */
    private fun currentOutput(): Map<String, String> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        var rank = -1
        var kind = "speaker"
        var name = ""
        for (d in am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            val t = d.type
            val (r, k) = when {
                t == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || (Build.VERSION.SDK_INT >= 31 && (t == android.media.AudioDeviceInfo.TYPE_BLE_HEADSET || t == android.media.AudioDeviceInfo.TYPE_BLE_SPEAKER)) -> 3 to "bluetooth"
                t == android.media.AudioDeviceInfo.TYPE_USB_DEVICE || t == android.media.AudioDeviceInfo.TYPE_USB_HEADSET -> 2 to "usb"
                t == android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES || t == android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET || t == android.media.AudioDeviceInfo.TYPE_LINE_ANALOG -> 1 to "wired"
                t == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> 0 to "speaker"
                else -> -1 to ""
            }
            if (r > rank) {
                rank = r
                kind = k
                name = if (k == "bluetooth" || k == "usb") (d.productName?.toString() ?: "") else ""
            }
        }
        return mapOf("kind" to kind, "name" to name)
    }

    private val outCallback = object : android.media.AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out android.media.AudioDeviceInfo>?) { emit(mapOf("type" to "out") + currentOutput()) }
        override fun onAudioDevicesRemoved(removed: Array<out android.media.AudioDeviceInfo>?) { emit(mapOf("type" to "out") + currentOutput()) }
    }

    private val plugReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            if (isInitialStickyBroadcast) return
            if (i?.action == Intent.ACTION_HEADSET_PLUG && i.getIntExtra("state", 0) == 1) {
                emit(mapOf("type" to "cmd", "name" to "plugged"))
            }
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(plugReceiver) } catch (_: Exception) { }
        try { (getSystemService(Context.AUDIO_SERVICE) as AudioManager).unregisterAudioDeviceCallback(outCallback) } catch (_: Exception) { }
        try { player.removeListener(listener) } catch (_: Exception) { }
        ui.removeCallbacksAndMessages(null)
        PlayerHolder.remote = null
        controller?.let { MediaController.releaseFuture(it) }
        if (isFinishing) { try { player.stop(); player.clearMediaItems() } catch (_: Exception) { } }
        super.onDestroy()
    }

    private fun emit(map: Map<String, Any?>) {
        ui.post { events?.success(map) }
    }

    // ------------------------------------------------------------------ calls from Dart
    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickFolder" -> {
                    if (pending != null) { result.error("busy", "A picker is already open.", null); return }
                    pending = result
                    val i = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                    )
                    if (call.argument<Boolean>("drive") == true) {
                        // Open Android's picker on Google Drive (the Drive app provides it). Without the app there is nothing to open.
                        val has = try { packageManager.resolveContentProvider(DRIVE_AUTH, 0) != null } catch (_: Exception) { false }
                        if (!has) { pending = null; result.error("nodrive", "The Google Drive app is not installed on this phone.", null); return }
                        if (Build.VERSION.SDK_INT >= 26) i.putExtra(DocumentsContract.EXTRA_INITIAL_URI, DocumentsContract.buildDocumentUri(DRIVE_AUTH, "root"))
                    }
                    startActivityForResult(i, REQ_TREE)
                }
                "pickFiles" -> {
                    if (pending != null) { result.error("busy", "A picker is already open.", null); return }
                    val drive = call.argument<Boolean>("drive") == true
                    if (drive) {
                        val has = try { packageManager.resolveContentProvider(DRIVE_AUTH, 0) != null } catch (_: Exception) { false }
                        if (!has) { result.error("nodrive", "The Google Drive app is not installed on this phone.", null); return }
                    }
                    pickingDrive = drive
                    pending = result
                    val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "application/ogg", "application/octet-stream"))
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        if (drive && Build.VERSION.SDK_INT >= 26) {
                            // Open the picker where the person last picked Drive songs, or on Drive itself the first time.
                            val last = getSharedPreferences("athana_native", MODE_PRIVATE).getString("driveInit", null)
                            val init = if (last != null) Uri.parse(last) else DocumentsContract.buildDocumentUri(DRIVE_AUTH, "root")
                            putExtra(DocumentsContract.EXTRA_INITIAL_URI, init)
                        }
                    }
                    startActivityForResult(i, REQ_FILES)
                }
                "scanTree" -> {
                    val tree = Uri.parse(call.argument<String>("tree")!!)
                    scanner.execute {
                        val songs = try { if (hasAccess(tree)) scanFolder(tree).songs else null } catch (e: Exception) { null }
                        ui.post { result.success(songs) }
                    }
                }
                "releaseTree" -> {
                    try {
                        contentResolver.releasePersistableUriPermission(Uri.parse(call.argument<String>("tree")!!), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: Exception) { }
                    result.success(null)
                }
                "meta" -> {
                    val uri = eff(Uri.parse(call.argument<String>("uri")!!))
                    val folderArt = call.argument<String>("folderArt") ?: ""
                    worker.execute {
                        val m = try { readMeta(uri, folderArt) } catch (e: Exception) { HashMap<String, Any>() }
                        ui.post { result.success(m) }
                    }
                }
                "play" -> {
                    curName = call.argument<String>("name") ?: ""
                    load(
                        call.argument<Int>("token") ?: 0,
                        Uri.parse(call.argument<String>("uri")!!),
                        call.argument<String>("title") ?: "",
                        call.argument<String>("artist") ?: "",
                        call.argument<String>("album") ?: "",
                        call.argument<String>("art") ?: "",
                        call.argument<Boolean>("aiff") ?: false
                    )
                    result.success(null)
                }
                "updateMeta" -> {
                    // Tags of a Drive song arrive a few seconds after it starts. Refresh the notification and lock screen without interrupting the music.
                    try {
                        val uri = call.argument<String>("uri") ?: ""
                        val cur = player.currentMediaItem
                        if (cur != null && !curAiff && curUri?.toString() == uri) {
                            val md = MediaMetadata.Builder()
                                .setTitle(call.argument<String>("title") ?: "")
                                .setArtist(call.argument<String>("artist") ?: "")
                                .setAlbumTitle(call.argument<String>("album") ?: "")
                            val art = call.argument<String>("art") ?: ""
                            if (art.isNotEmpty()) {
                                val f = File(art)
                                if (f.exists()) md.setArtworkData(f.readBytes(), MediaMetadata.PICTURE_TYPE_FRONT_COVER)
                            }
                            player.replaceMediaItem(player.currentMediaItemIndex, cur.buildUpon().setMediaMetadata(md.build()).build())
                        }
                    } catch (_: Exception) { }
                    result.success(null)
                }
                "offlineStart" -> {
                    val ok = try {
                        val items = (call.argument<List<Map<String, Any?>>>("items") ?: emptyList()).map { arrayOf((it["uri"] ?: "").toString(), (it["name"] ?: "").toString()) }
                        OfflineService.start(
                            applicationContext, items, call.argument<Boolean>("wifi") ?: true,
                            call.argument<Boolean>("force") ?: false, (call.argument<Number>("limit") ?: 0).toLong()
                        )
                        true
                    } catch (e: Exception) { android.util.Log.e("Athana", "offline start failed", e); false }
                    result.success(ok)
                }
                "warm" -> {
                    // The next Drive songs are copied to a temporary folder while this one plays (see Warm). An empty list clears them.
                    try {
                        val items = (call.argument<List<Map<String, Any?>>>("items") ?: emptyList()).map { arrayOf((it["uri"] ?: "").toString(), (it["name"] ?: "").toString()) }
                        Warm.request(applicationContext, call.argument<String>("current") ?: "", items, call.argument<Boolean>("wifi") ?: true)
                    } catch (e: Exception) { android.util.Log.e("Athana", "warm failed", e) }
                    result.success(null)
                }
                "bufInfo" -> {
                    // How far the playing song has loaded. Background jobs that read the same Drive file wait for this (see app_state).
                    val u = curUri
                    val local = u != null && eff(u) != u
                    val ahead = if (u == null) 0L else maxOf(0L, player.bufferedPosition - player.currentPosition)
                    val d = player.duration
                    val full = d > 0 && player.bufferedPosition >= d - 500
                    val settled = u == null || !isCloudUri(u) || local || full || ahead >= 30000L
                    updateStreamLow()
                    result.success(mapOf("settled" to settled, "local" to local, "ahead" to ahead))
                }
                "offlineStop" -> { OfflineService.pause(applicationContext); result.success(null) }
                "offlineClearQueue" -> { OfflineService.clearQueue(); result.success(null) }
                "offlineTrim" -> {
                    val limit = (call.argument<Number>("limit") ?: 0).toLong()
                    OfflineService.limitBytes = limit
                    worker.execute {
                        OfflineStore.trim(applicationContext, limit)
                        ui.post { result.success(null); OfflineService.emit(applicationContext) }
                    }
                }
                "offlineStatus" -> result.success(OfflineService.status(applicationContext))
                "offlineClear" -> {
                    OfflineService.stop()
                    worker.execute {
                        var w = 0
                        while (OfflineService.running && w < 40) { try { Thread.sleep(100) } catch (_: InterruptedException) { }; w++ }
                        OfflineStore.clear(applicationContext)
                        ui.post { result.success(null); OfflineService.emit(applicationContext) }
                    }
                }
                "resume" -> { player.play(); result.success(null) }
                "pause" -> { player.pause(); result.success(null) }
                "stop" -> { player.stop(); player.clearMediaItems(); result.success(null) }
                "seek" -> { player.seekTo((call.argument<Number>("ms") ?: 0).toLong()); result.success(null) }
                "setSpeed" -> {
                    val r = (call.argument<Double>("rate") ?: 1.0).toFloat()
                    val before = player.playbackParameters.speed
                    player.playbackParameters = PlaybackParameters(r, 1f)   // pitch stays the same
                    // Tempo is done by the standard audio chain. When Athana's own output has the song, going to or from normal speed
                    // makes the player re-open the song at the same spot so the right output takes over.
                    if (AthanaEngine.outEnabled(this) && (before == 1f) != (r == 1f) &&
                        (player.playbackState == Player.STATE_READY || player.playbackState == Player.STATE_BUFFERING)) {
                        val pos = player.currentPosition
                        val wasPlaying = player.playWhenReady
                        player.stop()
                        player.prepare()
                        player.seekTo(pos)
                        player.playWhenReady = wasPlaying
                    }
                    result.success(null)
                }
                "eqSet" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    val pre = (call.argument<Double>("pre") ?: 0.0).toFloat()
                    val g = call.argument<List<Double>>("gains") ?: emptyList()
                    val arr = FloatArray(10) { i -> (g.getOrNull(i) ?: 0.0).toFloat() }
                    val toggled = EqState.set(on, pre, arr)
                    // Switching on or off changes how the audio chain is built, so the player re-opens the song at the same spot.
                    if (toggled && (player.playbackState == Player.STATE_READY || player.playbackState == Player.STATE_BUFFERING)) {
                        val pos = player.currentPosition
                        player.stop()
                        player.prepare()
                        player.seekTo(pos)
                    }
                    result.success(null)
                }
                "mixSet" -> {
                    val toggled = EqState.setMix(
                        call.argument<Boolean>("active") ?: false,
                        (call.argument<Double>("bal") ?: 0.0).toFloat(),
                        (call.argument<Double>("wide") ?: 0.0).toFloat(),
                        call.argument<Boolean>("mono") ?: false,
                        (call.argument<Double>("vol") ?: 1.0).toFloat(),
                        (call.argument<Double>("cross") ?: 0.0).toFloat(),
                    )
                    if (toggled && (player.playbackState == Player.STATE_READY || player.playbackState == Player.STATE_BUFFERING)) {
                        val pos = player.currentPosition
                        player.stop()
                        player.prepare()
                        player.seekTo(pos)
                    }
                    result.success(null)
                }
                "saveCoverBytes" -> {
                    // A cover that was downloaded (Find cover and tags online): saved the same way as a cover from a file.
                    val bytes = call.argument<ByteArray>("bytes")
                    worker.execute {
                        val path = try { if (bytes != null && bytes.isNotEmpty()) saveCover(bytes, "") else "" } catch (e: Exception) { "" }
                        ui.post { result.success(path) }
                    }
                }
                "pickImage" -> {
                    if (pending != null) { result.error("busy", "A picker is already open.", null); return }
                    pending = result
                    pickingCover = call.argument<Boolean>("cover") ?: false
                    val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "image/*"
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivityForResult(i, REQ_IMAGE)
                }
                "saveText" -> {
                    // Lets the user choose where to save a text file (the lyrics backup). Returns true when it was written.
                    if (pending != null) { result.error("busy", "A picker is already open.", null); return }
                    pending = result
                    pendingSaveText = call.argument<String>("text") ?: ""
                    val i = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "athana-lyrics.json")
                    }
                    startActivityForResult(i, REQ_SAVE)
                }
                "pickText" -> {
                    // A lyrics file (.lrc or .txt): returns its text, or null when nothing was picked.
                    if (pending != null) { result.error("busy", "A picker is already open.", null); return }
                    pending = result
                    pickBig = call.argument<Boolean>("big") == true
                    val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/*", "application/octet-stream", "application/x-subrip"))
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivityForResult(i, REQ_TEXT)
                }
                "openUrl" -> {
                    val ok = try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url") ?: "")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        true
                    } catch (_: Exception) { false }
                    result.success(ok)
                }
                "lyrics" -> {
                    val uri = eff(Uri.parse(call.argument<String>("uri")!!))
                    worker.execute {
                        val text = try { LyricsReader.read(applicationContext, uri) } catch (_: Exception) { null }
                        ui.post { result.success(text) }
                    }
                }
                "normSet" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    normTarget = (call.argument<Double>("target") ?: -18.0)
                    val g = if (on) curLoud?.let { normGainFor(it, normTarget) } ?: 0f else 0f
                    val toggled = EqState.setNorm(on, g)
                    if (toggled && (player.playbackState == Player.STATE_READY || player.playbackState == Player.STATE_BUFFERING)) {
                        val pos = player.currentPosition
                        player.stop()
                        player.prepare()
                        player.seekTo(pos)
                    }
                    if (on) startNorm() else emit(mapOf("type" to "norm", "tok" to tok, "state" to "off"))
                    result.success(null)
                }
                "moveToBack" -> { moveTaskToBack(true); result.success(null) }
                "headset" -> {
                    val a1 = call.argument<String>("a1") ?: "playpause"
                    val a2 = call.argument<String>("a2") ?: "next"
                    val a3 = call.argument<String>("a3") ?: "prev"
                    PlayerHolder.headset = arrayOf(a1, a2, a3)
                    player.setHandleAudioBecomingNoisy(call.argument<Boolean>("unplugPause") ?: true)
                    result.success(null)
                }
                "analyze" -> {
                    val uri = eff(Uri.parse(call.argument<String>("uri")!!))
                    val aiff = call.argument<Boolean>("aiff") ?: false
                    val bits = call.argument<Int>("bits") ?: 0
                    val hint = (call.argument<Number>("durationMs") ?: 0).toLong()
                    val my = ++anTok
                    analyzer.execute {
                        val r = try {
                            SongAnalyzer.run(applicationContext, uri, aiff, bits, hint, { my != anTok }) { p -> emit(mapOf("type" to "an", "p" to p.toDouble())) }
                        } catch (e: Throwable) { android.util.Log.e("Athana", "analysis failed", e); null }
                        ui.post {
                            if (r == null) {
                                // Cancelled (another analysis started, or the song changed): no error, just nothing.
                                if (my != anTok) result.success(null) else result.error("analysis", SongAnalyzer.lastError.ifEmpty { "unknown" }, null)
                            } else result.success(hashMapOf<String, Any?>(
                                "rate" to r.rate, "channels" to r.channels, "peak" to r.peakDb, "clip" to r.clip,
                                "lufs" to r.lufs, "dr" to r.dr, "bits" to r.bits, "eff" to r.eff, "cutoff" to r.cutoff,
                                "cols" to r.cols, "h" to r.h, "spec" to r.spec,
                            ))
                        }
                    }
                }
                "loopSet" -> {
                    loopA = (call.argument<Number>("a") ?: -1).toLong()
                    loopB = (call.argument<Number>("b") ?: -1).toLong()
                    fxKick()
                    result.success(null)
                }
                "sleepFade" -> {
                    sleepStart = android.os.SystemClock.uptimeMillis()
                    sleepDur = ((call.argument<Number>("sec") ?: 8).toDouble() * 1000).toLong()
                    fxKick()
                    result.success(null)
                }
                "sleepFadeCancel" -> {
                    sleepDur = 0
                    fxKick()
                    result.success(null)
                }
                "fadeSet" -> {
                    fadeMs = ((call.argument<Number>("sec") ?: 0).toDouble() * 1000).toLong()
                    fxKick()
                    result.success(null)
                }
                "analyzeCancel" -> { anTok++; result.success(null) }
                "output" -> { result.success(currentOutput()) }
                "updateDir" -> {
                    val d = File(cacheDir, "updates").apply { mkdirs() }
                    d.listFiles()?.forEach { try { it.delete() } catch (_: Exception) { } }   // an older download is not needed any more
                    result.success(d.absolutePath)
                }
                "installApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    val f = File(path)
                    if (!f.exists()) { result.success("missing"); return }
                    if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                        // Android asks once for permission to install apps from Athana.
                        startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        result.success("permission")
                        return
                    }
                    val u = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.files", f)
                    startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(u, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                    result.success("ok")
                }
                "offlineRekey" -> {
                    val o = call.argument<String>("old") ?: ""
                    val n = call.argument<String>("new") ?: ""
                    worker.execute {
                        try { OfflineStore.rekey(applicationContext, o, n) } catch (e: Exception) { android.util.Log.e("Athana", "rekey failed", e) }
                        ui.post { result.success(null) }
                    }
                }
                "treeAccess" -> {
                    // Folders Android still lets Athana read. A folder missing here must be linked again.
                    result.success(contentResolver.persistedUriPermissions.filter { it.isReadPermission }.map { it.uri.toString() })
                }
                "keepAwake" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    if (on) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "engineGet" -> {
                    // Athana's own audio code: is the switch on, and is it playing the current song right now.
                    result.success(mapOf(
                        "flac" to AthanaEngine.enabled(this), "active" to (AthanaEngine.active.get() > 0),
                        "out" to AthanaEngine.outEnabled(this), "outActive" to AthanaEngine.outDesc.isNotEmpty(),
                        "bp" to AthanaEngine.bitPerfectEnabled(this),
                        "sFlac" to AthanaEngine.startedFlac, "sOut" to AthanaEngine.startedOut, "bpOn" to AthanaEngine.bitPerfect,
                        "flacNote" to AthanaEngine.flacNote, "outNote" to AthanaEngine.outNote, "bpNote" to AthanaEngine.bpNote,
                        "guard" to AthanaEngine.guardTripped(this)
                    ))
                }
                "engineSet" -> {
                    if (call.argument<Boolean>("flac") == true || call.argument<Boolean>("out") == true) AthanaEngine.clearGuard(this)
                    call.argument<Boolean>("flac")?.let { AthanaEngine.setEnabled(this, it) }
                    call.argument<Boolean>("out")?.let { AthanaEngine.setOutEnabled(this, it) }
                    call.argument<Boolean>("bp")?.let { AthanaEngine.setBitPerfectEnabled(this, it) }
                    result.success(null)
                }
                "volumeGet" -> {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    result.success(mapOf(
                        "cur" to am.getStreamVolume(AudioManager.STREAM_MUSIC),
                        "max" to am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    ))
                }
                "volumeSet" -> {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val lv = (call.argument<Int>("level") ?: 0).coerceIn(0, am.getStreamMaxVolume(AudioManager.STREAM_MUSIC))
                    am.setStreamVolume(AudioManager.STREAM_MUSIC, lv, 0)
                    result.success(null)
                }
                "volume" -> {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val dir = call.argument<Int>("dir") ?: 0
                    val d = when {
                        dir > 0 -> AudioManager.ADJUST_RAISE
                        dir < 0 -> AudioManager.ADJUST_LOWER
                        else -> AudioManager.ADJUST_TOGGLE_MUTE
                    }
                    am.adjustStreamVolume(AudioManager.STREAM_MUSIC, d, AudioManager.FLAG_SHOW_UI)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            android.util.Log.e("Athana", "call ${call.method} failed", e)
            pending = if (call.method.startsWith("pick")) null else pending
            result.error("native", e.message ?: e.javaClass.simpleName, null)
        }
    }

    // ------------------------------------------------------------------ pickers
    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_IMAGE) {
            val res = pending
            pending = null
            if (res == null) return
            val u = data?.data
            if (resultCode != RESULT_OK || u == null) { res.success(null); return }
            worker.execute {
                val cover = pickingCover
                val path = try { if (cover) saveCustomCover(u) else saveWallpaper(u) } catch (e: Exception) { android.util.Log.e("Athana", "image failed", e); null }
                ui.post { res.success(path) }
            }
            return
        }
        if (requestCode == REQ_SAVE) {
            val res = pending
            pending = null
            if (res == null) return
            val u = data?.data
            val text = pendingSaveText
            pendingSaveText = ""
            if (resultCode != RESULT_OK || u == null) { res.success(false); return }
            worker.execute {
                val ok = try {
                    contentResolver.openOutputStream(u, "wt")?.use { it.write(text.toByteArray(Charsets.UTF_8)) } != null
                } catch (e: Exception) { android.util.Log.e("Athana", "save failed", e); false }
                ui.post { res.success(ok) }
            }
            return
        }
        if (requestCode == REQ_TEXT) {
            val res = pending
            pending = null
            if (res == null) return
            val u = data?.data
            if (resultCode != RESULT_OK || u == null) { res.success(null); return }
            worker.execute {
                val text = try { readLyricsText(u) } catch (e: Exception) { android.util.Log.e("Athana", "lyrics file failed", e); null }
                ui.post { res.success(text) }
            }
            return
        }
        if (requestCode == REQ_TREE || requestCode == REQ_FILES) {
            val res = pending
            pending = null
            if (res == null) return
            if (resultCode != RESULT_OK || data == null) { res.success(null); return }
            if (requestCode == REQ_TREE) handleTree(res, data.data) else {
                if (pickingDrive) rememberDriveFolder(data)
                handleFiles(res, data)
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    @Volatile private var pickBig = false
    @Volatile private var pendingSaveText = ""

    /** Reads a small lyrics file as text (UTF-8, or UTF-16 when it has a byte-order mark). Files over 1 MB are refused (40 MB for a backup). */
    private fun readLyricsText(u: Uri): String? {
        val bytes = contentResolver.openInputStream(u)?.use { it.readBytes() } ?: return null
        if (bytes.size > (if (pickBig) 40_000_000 else 1_000_000)) return null
        if (bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte()) return String(bytes, 2, bytes.size - 2, Charsets.UTF_16LE)
        if (bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte()) return String(bytes, 2, bytes.size - 2, Charsets.UTF_16BE)
        val s = String(bytes, Charsets.UTF_8)
        return if (s.startsWith("\uFEFF")) s.substring(1) else s
    }

    private var pickingDrive = false

    /** Remembers the Drive folder the songs came from, so the next Drive pick opens in the same place. */
    private fun rememberDriveFolder(data: Intent) {
        if (Build.VERSION.SDK_INT < 26) return
        val first = data.data ?: data.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri ?: return
        worker.execute {
            try {
                if (first.authority != DRIVE_AUTH) return@execute
                val ids = DocumentsContract.findDocumentPath(contentResolver, first)?.path ?: return@execute
                if (ids.size < 2) return@execute
                val parent = DocumentsContract.buildDocumentUri(DRIVE_AUTH, ids[ids.size - 2])
                getSharedPreferences("athana_native", MODE_PRIVATE).edit().putString("driveInit", parent.toString()).apply()
            } catch (_: Throwable) { }
        }
    }

    /** Shrinks the chosen picture to at most 2560 px and keeps it as a JPEG inside the app. Returns its path. */
    private var pickingCover = false
    /** A picture chosen as a song's cover: shrunk to 1200 pixels and kept in the app's own folder. */
    private fun saveCustomCover(u: Uri): String? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1200) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bmp = contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it, null, opts) } ?: return null
        val big = maxOf(bmp.width, bmp.height)
        if (big > 1200) {
            val k = 1200f / big
            bmp = Bitmap.createScaledBitmap(bmp, (bmp.width * k).toInt().coerceAtLeast(1), (bmp.height * k).toInt().coerceAtLeast(1), true)
        }
        val dir = File(filesDir, "covers").apply { mkdirs() }
        val out = File(dir, "cover_" + System.currentTimeMillis() + ".jpg")
        FileOutputStream(out).use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
        return out.absolutePath
    }

    private fun saveWallpaper(u: Uri): String? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 2560) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bmp = contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it, null, opts) } ?: return null
        val big = maxOf(bmp.width, bmp.height)
        if (big > 2560) {
            val k = 2560f / big
            bmp = Bitmap.createScaledBitmap(bmp, (bmp.width * k).toInt().coerceAtLeast(1), (bmp.height * k).toInt().coerceAtLeast(1), true)
        }
        filesDir.listFiles { f -> f.name.startsWith("wallpaper_") }?.forEach { it.delete() }
        val out = File(filesDir, "wallpaper_" + System.currentTimeMillis() + ".jpg")
        FileOutputStream(out).use { bmp.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        return out.absolutePath
    }

    private fun handleTree(res: MethodChannel.Result, tree: Uri?) {
        if (tree == null) { res.success(null); return }
        var kept = true
        try { contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) { kept = false }
        scanner.execute {
            val found = try { scanFolder(tree) } catch (e: Exception) { android.util.Log.e("Athana", "folder scan failed", e); null }
            ui.post {
                if (found == null) res.error("scan", "The folder could not be read.", null)
                else res.success(hashMapOf("tree" to tree.toString(), "name" to found.name, "songs" to found.songs, "kept" to kept))
            }
        }
    }

    private fun handleFiles(res: MethodChannel.Result, data: Intent) {
        val uris = ArrayList<Uri>()
        data.clipData?.let { cd -> for (i in 0 until cd.itemCount) uris.add(cd.getItemAt(i).uri) }
        data.data?.let { uris.add(it) }
        scanner.execute {
            val songs = ArrayList<Map<String, Any>>()
            for (u in uris) {
                recoverFailed.remove(u.toString())
                var kept = true
                try {
                    contentResolver.takePersistableUriPermission(u, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    android.util.Log.i("Athana", "picked ok, permission kept: $u")
                } catch (e: Exception) {
                    kept = false
                    android.util.Log.w("Athana", "picked, permission NOT kept (${e.javaClass.simpleName}: ${e.message}), android ${Build.VERSION.SDK_INT}, kept so far ${contentResolver.persistedUriPermissions.size}: $u")
                }
                try {
                    contentResolver.query(u, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                        if (c.moveToFirst()) {
                            val name = c.getString(0) ?: return@use
                            val size = if (c.isNull(1)) -1L else c.getLong(1)
                            if (audioRe.matches(name)) songs.add(hashMapOf("uri" to u.toString(), "name" to name, "size" to size, "folder" to "", "folderArt" to "", "kept" to kept))
                        }
                    }
                } catch (_: Exception) { }
            }
            ui.post { res.success(songs) }
        }
    }

    private fun hasAccess(tree: Uri): Boolean =
        contentResolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission }

    private class FoundSong(val name: String, val size: Long, val uri: Uri, val modified: Long)

    private class FolderScan(val name: String, val songs: List<Map<String, Any>>)

    /** Lists every song in the folder and its sub-folders, with the folder's cover picture if there is one. */
    private fun scanFolder(tree: Uri): FolderScan {
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        var rootName = "Folder"
        try {
            contentResolver.query(
                DocumentsContract.buildDocumentUriUsingTree(tree, rootId),
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null
            )?.use { c -> if (c.moveToFirst()) rootName = c.getString(0) ?: rootName }
        } catch (_: Exception) { }
        val cols = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED
        )
        val songs = ArrayList<Map<String, Any>>()

        fun walk(dirId: String, rel: String, depth: Int) {
            if (depth > 12 || songs.size >= 20000) return
            val sub = ArrayList<Pair<String, String>>()
            val here = ArrayList<FoundSong>()
            val pics = ArrayList<Pair<String, Uri>>()
            // Cloud providers such as Google Drive answer "still loading" first and fill the list in a moment later. Ask again until it is complete.
            var tries = 0
            while (true) {
                sub.clear(); here.clear(); pics.clear()
                var loading = false
                contentResolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, dirId), cols, null, null, null)?.use { c ->
                    loading = c.extras?.getBoolean(DocumentsContract.EXTRA_LOADING, false) == true
                    while (c.moveToNext()) {
                        val id = c.getString(0) ?: continue
                        val name = c.getString(1) ?: continue
                        val mime = c.getString(2) ?: ""
                        val size = if (c.isNull(3)) -1L else c.getLong(3)
                        val mod = if (c.isNull(4)) 0L else c.getLong(4)
                        when {
                            mime == DocumentsContract.Document.MIME_TYPE_DIR -> sub.add(id to "$rel/$name")
                            audioRe.matches(name) -> here.add(FoundSong(name, size, DocumentsContract.buildDocumentUriUsingTree(tree, id), mod))
                            imageRe.matches(name) -> pics.add(name to DocumentsContract.buildDocumentUriUsingTree(tree, id))
                        }
                    }
                }
                if (!loading || ++tries > 60) break
                try { Thread.sleep(500) } catch (_: InterruptedException) { break }
            }
            val art = (pics.firstOrNull { coverRe.containsMatchIn(it.first) } ?: pics.firstOrNull())?.second?.toString() ?: ""
            for (f in here) {
                songs.add(hashMapOf("uri" to f.uri.toString(), "name" to f.name, "size" to f.size, "modified" to f.modified, "folder" to rel, "folderArt" to art))
            }
            for ((id, r) in sub) walk(id, r, depth + 1)
        }
        walk(rootId, rootName, 0)
        return FolderScan(rootName, songs)
    }

    // ------------------------------------------------------------------ song details and covers
    private fun readMeta(uri: Uri, folderArt: String): HashMap<String, Any> {
        val out = HashMap<String, Any>()
        var embedded: ByteArray? = null
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(this, uri)
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.let { out["title"] = it }
            (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST))?.let { out["artist"] = it }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)?.let { out["album"] = it }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.let { out["durationMs"] = it }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)?.let { out["albumArtist"] = it }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE)?.let { out["genre"] = it }
            (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR) ?: r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE))?.let { out["year"] = it }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_COMPOSER)?.let { out["composer"] = it }
            if (Build.VERSION.SDK_INT >= 31) {
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)?.toIntOrNull()?.let { out["rate"] = it }
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITS_PER_SAMPLE)?.toIntOrNull()?.let { out["bits"] = it }
            }
            embedded = r.embeddedPicture
        } catch (_: Exception) {
            // formats Android cannot read tags from (for example AIFF) are handled just below
        } finally {
            try { r.release() } catch (_: Exception) { }
        }
        // AIFF / WAV keep their tags and cover in an "ID3 " chunk that Android's own reader cannot see
        if (embedded == null || !out.containsKey("title") || !out.containsKey("artist")) {
            try {
                ContainerTags.read(this, uri)?.let { t ->
                    if (embedded == null) embedded = t.picture
                    if (!out.containsKey("title")) t.title?.takeIf { it.isNotBlank() }?.let { out["title"] = it }
                    if (!out.containsKey("artist")) t.artist?.takeIf { it.isNotBlank() }?.let { out["artist"] = it }
                    if (!out.containsKey("album")) t.album?.takeIf { it.isNotBlank() }?.let { out["album"] = it }
                    if (!out.containsKey("albumArtist")) t.albumArtist?.takeIf { it.isNotBlank() }?.let { out["albumArtist"] = it }
                    if (!out.containsKey("genre")) t.genre?.takeIf { it.isNotBlank() }?.let { out["genre"] = it }
                    if (!out.containsKey("year")) t.year?.takeIf { it.isNotBlank() }?.let { out["year"] = it }
                    if (!out.containsKey("composer")) t.composer?.takeIf { it.isNotBlank() }?.let { out["composer"] = it }
                    if (!out.containsKey("rate") && t.rate > 0) out["rate"] = t.rate
                    if (!out.containsKey("bits") && t.bits > 0) out["bits"] = t.bits
                    if (!out.containsKey("durationMs") && t.durationMs > 0) out["durationMs"] = t.durationMs
                }
            } catch (_: Exception) { }
        }
        // Android 11 and older cannot tell the sample rate or bit depth of a song, so a FLAC file is read here directly.
        if (!out.containsKey("rate") || !out.containsKey("bits")) {
            try {
                flacInfo(uri)?.let { fi ->
                    if (!out.containsKey("rate")) out["rate"] = fi[0]
                    if (!out.containsKey("bits")) out["bits"] = fi[1]
                    if (!out.containsKey("durationMs") && fi[0] > 0 && fi[2] > 0) out["durationMs"] = fi[2].toLong() * 1000L / fi[0]
                }
            } catch (_: Exception) { }
        }
        if (!out.containsKey("rate")) {
            val ex = android.media.MediaExtractor()
            try {
                ex.setDataSource(this, uri, null)
                if (ex.trackCount > 0) {
                    val f = ex.getTrackFormat(0)
                    if (f.containsKey(android.media.MediaFormat.KEY_SAMPLE_RATE)) out["rate"] = f.getInteger(android.media.MediaFormat.KEY_SAMPLE_RATE)
                }
            } catch (_: Exception) {
            } finally {
                try { ex.release() } catch (_: Exception) { }
            }
        }
        out["art"] = try { saveCover(embedded, folderArt) } catch (_: Exception) { "" }
        return out
    }

    /**
     * Reads the STREAMINFO block at the start of a FLAC file: [sample rate, bits per sample, total samples (clipped to Int)].
     * Null when the file is not FLAC. A tag block (ID3) in front of the "fLaC" mark is skipped.
     */
    private fun flacInfo(uri: Uri): IntArray? {
        val ins = contentResolver.openInputStream(uri) ?: return null
        ins.use { st ->
            fun readFull(b: ByteArray, len: Int): Boolean {
                var n = 0
                while (n < len) {
                    val r = st.read(b, n, len - n)
                    if (r < 0) return false
                    n += r
                }
                return true
            }
            val head = ByteArray(10)
            if (!readFull(head, 4)) return null
            if (head[0] == 'I'.code.toByte() && head[1] == 'D'.code.toByte() && head[2] == '3'.code.toByte()) {
                if (!readFull(head, 6)) return null            // the rest of the 10-byte ID3 header (head[0..3] were the first four)
                // head now holds bytes 4..9 of the header: version, flags, 4 size bytes
                val size = ((head[2].toInt() and 0x7F) shl 21) or ((head[3].toInt() and 0x7F) shl 14) or ((head[4].toInt() and 0x7F) shl 7) or (head[5].toInt() and 0x7F)
                var left = size.toLong() + (if ((head[1].toInt() and 0x10) != 0) 10 else 0)
                while (left > 0) {
                    val k = st.skip(left)
                    if (k <= 0) { if (st.read() < 0) return null else left-- } else left -= k
                }
                if (!readFull(head, 4)) return null
            }
            if (head[0] != 'f'.code.toByte() || head[1] != 'L'.code.toByte() || head[2] != 'a'.code.toByte() || head[3] != 'C'.code.toByte()) return null
            val b = ByteArray(38)                                // block header (4) + STREAMINFO start (34)
            if (!readFull(b, 38)) return null
            if ((b[0].toInt() and 0x7F) != 0) return null        // the first block must be STREAMINFO
            val o = 4
            val rate = ((b[o + 10].toInt() and 0xFF) shl 12) or ((b[o + 11].toInt() and 0xFF) shl 4) or ((b[o + 12].toInt() and 0xFF) shr 4)
            val bits = ((((b[o + 12].toInt() and 0x01) shl 4) or ((b[o + 13].toInt() and 0xFF) shr 4)) + 1)
            val total = ((b[o + 13].toLong() and 0x0FL) shl 32) or ((b[o + 14].toLong() and 0xFFL) shl 24) or
                ((b[o + 15].toLong() and 0xFFL) shl 16) or ((b[o + 16].toLong() and 0xFFL) shl 8) or (b[o + 17].toLong() and 0xFFL)
            if (rate <= 0) return null
            return intArrayOf(rate, bits, if (total > Int.MAX_VALUE) Int.MAX_VALUE else total.toInt())
        }
    }

    /** A small JPEG per album (same picture = same file), used by the app and the notification. Returns its path or "". */
    private fun saveCover(embedded: ByteArray?, folderArt: String): String {
        val key = when {
            embedded != null && embedded.isNotEmpty() -> sha1(embedded)
            folderArt.isNotEmpty() -> sha1(folderArt.toByteArray())
            else -> return ""
        }
        val dir = File(filesDir, "art").apply { mkdirs() }
        val f = File(dir, "$key.jpg")
        if (f.exists() && f.length() > 0) return f.absolutePath
        val bytes = if (embedded != null && embedded.isNotEmpty()) embedded
        else contentResolver.openInputStream(Uri.parse(folderArt))?.use { it.readBytes() } ?: return ""
        val bmp = decodeSmall(bytes) ?: return ""
        FileOutputStream(f).use { bmp.compress(Bitmap.CompressFormat.JPEG, 86, it) }
        bmp.recycle()
        return f.absolutePath
    }

    private fun decodeSmall(b: ByteArray): Bitmap? {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(b, 0, b.size, o)
        var s = 1
        val big = maxOf(o.outWidth, o.outHeight)
        while (big / (s * 2) >= 600) s *= 2
        return BitmapFactory.decodeByteArray(b, 0, b.size, BitmapFactory.Options().apply { inSampleSize = s })
    }

    private fun sha1(b: ByteArray): String =
        MessageDigest.getInstance("SHA-1").digest(b).joinToString("") { "%02x".format(it) }

    /**
     * A cloud app (Google Drive) sometimes hands out a file that cannot be streamed or jumped around in. When that happens,
     * the song is copied to the phone from start to end, which always works, and then played from the copy.
     */
    private fun tryRecover(error: PlaybackException): Boolean {
        val uri = curUri ?: return false
        val key = uri.toString()
        val code = error.errorCode
        // Also try the copy-to-phone recovery when the cloud app refuses access (ERROR_CODE_IO_NO_PERMISSION).
        val io = code == PlaybackException.ERROR_CODE_IO_UNSPECIFIED ||
            code == PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE ||
            code == PlaybackException.ERROR_CODE_IO_NO_PERMISSION
        if (!io || uri.scheme != "content" || curAiff || recovering == key) return false
        if (OfflineStore.find(applicationContext, key) != null) return false
        val last = recoverFailed[key]
        if (last != null && System.currentTimeMillis() - last < 30000) return false
        val ll = lastLoad ?: return false
        val myTok = tok
        val songName = curName
        recovering = key
        emit(mapOf("type" to "prep", "tok" to myTok, "on" to true))
        Thread {
            // Why the copy failed, so the message can say what to do: perm, missing, space or the system's own words.
            var why = ""
            val ok = try {
                OfflineService.copyOne(applicationContext, key, songName, false)
            } catch (e: Throwable) {
                android.util.Log.e("Athana", "copy before playing failed", e)
                why = when (e) {
                    is SecurityException -> "perm"
                    is java.io.FileNotFoundException -> "missing"
                    is OfflineNoSpace -> "space"
                    else -> (e.javaClass.simpleName + ": " + (e.message ?: "")).take(120)
                }
                false
            }
            ui.post {
                recovering = null
                emit(mapOf("type" to "prep", "tok" to myTok, "on" to false))
                if (tok != myTok || curUri?.toString() != key) return@post
                if (ok) {
                    load(ll[0] as Int, ll[1] as Uri, ll[2] as String, ll[3] as String, ll[4] as String, ll[5] as String, false)
                } else {
                    recoverFailed[key] = System.currentTimeMillis()
                    player.playWhenReady = false
                    emit(mapOf("type" to "error", "tok" to myTok, "name" to error.errorCodeName, "cloud" to true, "why" to why))
                }
            }
        }.apply { name = "athana-recover"; start() }
        return true
    }

    /** A song saved on the phone is read from its copy, so it needs no internet. Everything else is used as it is. */
    private fun eff(u: Uri): Uri =
        OfflineStore.find(applicationContext, u.toString())?.let { Uri.fromFile(it) }
            ?: Warm.find(applicationContext, u.toString())?.let { Uri.fromFile(it) }
            ?: u

    private val localHosts = setOf("com.android.externalstorage.documents", "com.android.providers.downloads.documents", "com.android.providers.media.documents", "media")

    /** A song behind a cloud app (Google Drive): a content link whose provider is not one of the phone's own. */
    private fun isCloudUri(u: Uri): Boolean = u.scheme == "content" && !u.host.isNullOrEmpty() && u.host !in localHosts

    /** Tells the temporary copier to wait while the song that is playing has less than 8 seconds loaded (main thread only). */
    private fun updateStreamLow() {
        val u = curUri
        Warm.streamLow = u != null && isCloudUri(u) && eff(u) == u && player.playbackState != Player.STATE_ENDED &&
            player.bufferedPosition - player.currentPosition < 8000L &&
            !(player.duration > 0 && player.bufferedPosition >= player.duration - 500)
    }

    // ------------------------------------------------------------------ playback
    private fun load(token: Int, uri: Uri, title: String, artist: String, album: String, art: String, aiff: Boolean) {
        tok = token
        android.util.Log.i("Athana", "play: $uri, permission kept=" + contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission })
        lastLoad = arrayOf(token, uri, title, artist, album, art, aiff)
        val md = MediaMetadata.Builder().setTitle(title).setArtist(artist).setAlbumTitle(album)
        if (art.isNotEmpty()) {
            try {
                val f = File(art)
                if (f.exists()) md.setArtworkData(f.readBytes(), MediaMetadata.PICTURE_TYPE_FRONT_COVER)
            } catch (_: Exception) { }
        }
        // Remember which saved song is playing: it is never removed, and playing it makes it "recent" for the storage limit.
        OfflineStore.playingKey = OfflineStore.key(uri.toString())
        OfflineStore.find(applicationContext, uri.toString())?.setLastModified(System.currentTimeMillis())
        val item = MediaItem.Builder().setUri(eff(uri)).setMediaMetadata(md.build()).build()
        if (aiff) {
            // Android cannot read AIFF, so it is presented to the player as WAV on the fly (no waiting, no copy).
            val source = ProgressiveMediaSource.Factory(
                DataSource.Factory { AiffWavDataSource(applicationContext) }, DefaultExtractorsFactory()
            ).createMediaSource(item)
            player.setMediaSource(source)
        } else {
            player.setMediaItem(item)
        }
        player.prepare()
        player.play()
        curUri = uri
        curAiff = aiff
        curLoud = null
        Warm.streamLow = false
        if (EqState.normOn) {
            EqState.updateNormGain(0f)
            startNorm()
        }
    }

    /** Finds out how loud the current song is (cached after the first time) and applies the matching gain. */
    private fun startNorm() {
        val uri = curUri ?: return
        val key = uri.toString()
        val myTok = tok
        val cached = loud.get(key)
        if (cached != null) { applyNorm(key, cached, myTok); return }
        if (measuring == key) return
        measuring = key
        emit(mapOf("type" to "norm", "tok" to myTok, "state" to "measuring"))
        normWhenSettled(uri, key, myTok, curAiff)
    }

    /** A streamed Drive song is measured only after it has loaded well ahead, so the measuring does not slow the music down. */
    private fun normWhenSettled(uri: Uri, key: String, myTok: Int, aiff: Boolean) {
        if (curUri?.toString() != key || !EqState.normOn) { if (measuring == key) measuring = null; return }
        if (isCloudUri(uri) && eff(uri) == uri) {
            val full = player.duration > 0 && player.bufferedPosition >= player.duration - 500
            if (!full && player.bufferedPosition - player.currentPosition < 25000L) {
                ui.postDelayed({ normWhenSettled(uri, key, myTok, aiff) }, 2000)
                return
            }
        }
        worker.execute {
            val r = LoudnessAnalyzer.measure(applicationContext, eff(uri), aiff) { curUri?.toString() != key || !EqState.normOn }
            if (measuring == key) measuring = null
            if (r != null) loud.put(key, r)
            if (curUri?.toString() == key && EqState.normOn) {
                if (r != null) applyNorm(key, r, myTok) else emit(mapOf("type" to "norm", "tok" to myTok, "state" to "failed"))
            }
        }
    }

    private fun applyNorm(key: String, r: LoudnessResult, myTok: Int) {
        if (curUri?.toString() != key) return
        curLoud = r
        val g = normGainFor(r, normTarget)
        EqState.updateNormGain(g)
        emit(mapOf("type" to "norm", "tok" to myTok, "state" to "ready", "gain" to g.toDouble(), "lufs" to r.lufs, "peak" to r.peakDb))
    }

    private fun push(ended: Boolean = false) {
        updateStreamLow()
        val dur = player.duration.let { if (it == C.TIME_UNSET) -1L else it }
        emit(mapOf(
            "type" to "state", "tok" to tok, "pos" to player.currentPosition, "dur" to dur,
            "playWhenReady" to player.playWhenReady, "playing" to player.isPlaying, "ended" to ended
        ))
    }

    private fun pushInfo() {
        val f = try { player.audioFormat } catch (_: Exception) { null }
        val out = (getSystemService(AUDIO_SERVICE) as AudioManager)
            .getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 0
        emit(mapOf("type" to "info", "tok" to tok, "mime" to (f?.sampleMimeType ?: ""), "rate" to (f?.sampleRate ?: 0), "outRate" to out, "own" to (AthanaEngine.active.get() > 0), "ownOut" to AthanaEngine.outDesc, "bp" to AthanaEngine.bitPerfect))
    }

    // A–B loop and fades between songs. They are checked often (every 40 ms) so a loop point is hit exactly and a fade is smooth.
    @Volatile private var loopA = -1L
    @Volatile private var loopB = -1L
    @Volatile private var fadeMs = 0L

    @Volatile private var sleepStart = 0L
    @Volatile private var sleepDur = 0L      // > 0 while the sleep timer is fading the music out

    private val fx = object : Runnable {
        override fun run() {
            if (!player.isPlaying) return
            val pos = player.currentPosition
            if (loopA >= 0 && loopB > loopA && pos >= loopB) player.seekTo(loopA)
            var vol = 1f
            if (fadeMs > 0) {
                val dur = player.duration
                var v = 1f
                if (pos < fadeMs) v = pos.toFloat() / fadeMs
                if (dur > 0 && dur - pos < fadeMs) v = minOf(v, (dur - pos).toFloat() / fadeMs)
                v = v.coerceIn(0f, 1f)
                vol = v * v
            }
            if (sleepDur > 0) {
                val m = 1f - (android.os.SystemClock.uptimeMillis() - sleepStart).toFloat() / sleepDur
                if (m <= 0f) {
                    sleepDur = 0
                    player.pause()
                    player.volume = 1f
                    return
                }
                vol *= m * m
            }
            if (fadeMs > 0 || sleepDur > 0) player.volume = vol
            if (fadeMs > 0 || loopB > 0 || sleepDur > 0) ui.postDelayed(this, 40)
        }
    }

    private fun fxKick() {
        ui.removeCallbacks(fx)
        if (fadeMs <= 0 && sleepDur <= 0) player.volume = 1f
        if (fadeMs > 0 || loopB > 0 || sleepDur > 0) ui.post(fx)
    }

    private val ticker = object : Runnable {
        override fun run() {
            if (player.isPlaying) { push(); ui.postDelayed(this, 250) }
        }
    }

    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            if (state == Player.STATE_READY) { pushInfo(); push() }
            if (state == Player.STATE_ENDED) { player.playWhenReady = false; push(ended = true) }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            ui.removeCallbacks(ticker)
            if (isPlaying) ui.post(ticker) else push()
            fxKick()
        }

        override fun onPlayerError(error: PlaybackException) {
            if (tryRecover(error)) return
            player.playWhenReady = false
            var status = ""
            var cause: Throwable? = error.cause
            while (cause != null) {
                if (cause.javaClass.simpleName == "InvalidResponseCodeException") {
                    try { status = cause.javaClass.getField("responseCode").getInt(cause).toString() } catch (_: Exception) { }
                    break
                }
                cause = cause.cause
            }
            emit(mapOf("type" to "error", "tok" to tok, "name" to error.errorCodeName, "cloud" to (curUri?.scheme == "content"), "why" to status))
        }
    }
}

// ---------------------------------------------------------------------- tags inside AIFF / WAV files
private class FileTags {
    var title: String? = null
    var artist: String? = null
    var album: String? = null
    var albumArtist: String? = null
    var genre: String? = null
    var year: String? = null
    var composer: String? = null
    var rate: Int = 0
    var bits: Int = 0
    var picture: ByteArray? = null
    var durationMs: Long = -1L
}

/** Reads the "ID3 " chunk of AIFF (FORM) and WAV (RIFF) files, plus the AIFF length. Android cannot do this itself. */
private object ContainerTags {
    fun read(ctx: Context, uri: Uri): FileTags? {
        val pfd = ctx.contentResolver.openFileDescriptor(uri, "r") ?: return null
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { ins ->
            val ch = ins.channel
            val total = ch.size()
            val head = readAt(ch, 0L, 12)
            if (head.size < 12) return@use null
            val form = String(head, 0, 4, Charsets.ISO_8859_1)
            val le = form == "RIFF"
            if (form != "FORM" && !le) return@use null
            val out = FileTags()
            var off = 12L
            while (off + 8 <= total) {
                val h = readAt(ch, off, 8)
                if (h.size < 8) break
                val id = String(h, 0, 4, Charsets.ISO_8859_1)
                val size = u32(h, 4, le)
                val body = off + 8
                if (id == "COMM" && !le && size >= 18) {
                    val d = readAt(ch, body, 18)
                    if (d.size >= 18) {
                        val frames = u32(d, 2, false)
                        val exp = (((d[8].toInt() and 0xFF) shl 8) or (d[9].toInt() and 0xFF)) and 0x7FFF
                        val rate = u32(d, 10, false).toDouble() * Math.pow(2.0, (exp - 16414).toDouble())
                        if (rate > 0) out.durationMs = (frames / rate * 1000.0).toLong()
                        if (rate > 0) out.rate = rate.toInt()
                        out.bits = ((d[6].toInt() and 0xFF) shl 8) or (d[7].toInt() and 0xFF)
                    }
                } else if (id == "fmt " && le && size >= 16) {
                    val d = readAt(ch, body, 16)
                    if (d.size >= 16) {
                        out.rate = u32(d, 4, true).toInt()
                        out.bits = (d[14].toInt() and 0xFF) or ((d[15].toInt() and 0xFF) shl 8)
                    }
                } else if (id.equals("id3 ", ignoreCase = true)) {
                    val tag = readAt(ch, body, minOf(size, 24_000_000L).toInt())
                    parseId3(tag, out)
                }
                off = body + size + (size and 1L)
            }
            out
        }
    }

    private fun readAt(ch: FileChannel, pos: Long, n: Int): ByteArray {
        val bb = ByteBuffer.allocate(n)
        var p = pos
        while (bb.hasRemaining()) {
            val r = ch.read(bb, p)
            if (r <= 0) break
            p += r
        }
        return bb.array().copyOf(bb.position())
    }

    private fun u32(b: ByteArray, o: Int, le: Boolean): Long {
        var v = 0L
        for (i in 0 until 4) v = (v shl 8) or (b[o + (if (le) 3 - i else i)].toLong() and 0xFF)
        return v
    }

    private fun syncsafe(b: ByteArray, o: Int): Int =
        ((b[o].toInt() and 0x7F) shl 21) or ((b[o + 1].toInt() and 0x7F) shl 14) or
            ((b[o + 2].toInt() and 0x7F) shl 7) or (b[o + 3].toInt() and 0x7F)

    private fun text(b: ByteArray, d: Int, e: Int): String {
        if (e <= d + 1) return ""
        val cs: Charset = when (b[d].toInt()) {
            1 -> Charsets.UTF_16
            2 -> Charsets.UTF_16BE
            3 -> Charsets.UTF_8
            else -> try { Charset.forName("windows-1252") } catch (_: Exception) { Charsets.ISO_8859_1 }
        }
        return String(b, d + 1, e - d - 1, cs).replace("﻿", "")
            .split('\u0000').filter { it.isNotEmpty() }.joinToString(", ")
    }

    private fun parseId3(b: ByteArray, out: FileTags) {
        if (b.size < 10 || b[0].toInt() != 73 || b[1].toInt() != 68 || b[2].toInt() != 51) return
        val ver = b[3].toInt()
        val end = minOf(b.size.toLong(), 10L + syncsafe(b, 6)).toInt()
        var p = 10
        while (p + 10 <= end) {
            val id = String(b, p, 4, Charsets.ISO_8859_1)
            if (!id.all { it in 'A'..'Z' || it in '0'..'9' }) break
            val sz = if (ver == 4) syncsafe(b, p + 4) else u32(b, p + 4, false).toInt()
            if (sz < 0) break
            val d = p + 10
            val e = minOf(d.toLong() + sz, b.size.toLong()).toInt()
            when (id) {
                "TIT2" -> if (out.title == null) out.title = text(b, d, e)
                "TPE1" -> if (out.artist == null) out.artist = text(b, d, e)
                "TPE2" -> if (out.albumArtist == null) out.albumArtist = text(b, d, e)
                "TCON" -> if (out.genre == null) out.genre = text(b, d, e)
                "TYER", "TDRC" -> if (out.year == null) out.year = text(b, d, e)
                "TCOM" -> if (out.composer == null) out.composer = text(b, d, e)
                "TALB" -> if (out.album == null) out.album = text(b, d, e)
                "APIC" -> if (out.picture == null && e > d + 4) {
                    val enc = b[d].toInt()
                    var q = d + 1
                    while (q < e && b[q].toInt() != 0) q++          // image type text
                    q += 2                                          // its end mark + the picture-type byte
                    if (enc == 1 || enc == 2) {
                        while (q + 1 < e && !(b[q].toInt() == 0 && b[q + 1].toInt() == 0)) q += 2
                        q += 2
                    } else {
                        while (q < e && b[q].toInt() != 0) q++
                        q++
                    }
                    if (q < e) out.picture = b.copyOfRange(q, e)
                }
            }
            p = d + sz
        }
    }
}

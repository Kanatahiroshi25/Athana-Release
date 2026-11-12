package com.athana.lossless

import android.content.Context
import android.os.Handler
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.annotation.OptIn
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink

/**
 * One ExoPlayer for the whole app, shared by the screen (MainActivity) and the background service (PlaybackService),
 * so music keeps playing when the screen is closed.
 */
@OptIn(UnstableApi::class)
object PlayerHolder {
    @Volatile private var player: ExoPlayer? = null
    private var crashGuard = false

    /** Set by MainActivity while the page is alive. Notification buttons are forwarded to the page through it. */
    @Volatile var remote: ((String) -> Unit)? = null

    /** What 1, 2 and 3 presses of a wired headset's centre button do. Set from Settings → Controls. */
    @Volatile var headset: Array<String> = arrayOf("playpause", "next", "prev")

    /**
     * Throws the player away, so the next one is built from scratch and reads the engine switches again.
     * Android often keeps Athana's process alive after the app is swiped away, and without this the old player (with the old
     * switch values) would still be there when Athana is opened again.
     */
    fun release() {
        synchronized(this) {
            try { player?.release() } catch (_: Exception) { }
            player = null
        }
    }

    fun get(context: Context): ExoPlayer {
        player?.let { return it }
        synchronized(this) {
            player?.let { return it }
            val app = context.applicationContext
            // Float output is deliberately NOT enabled. It only affects files above 16-bit (24/32-bit FLAC, WAV, AIFF), and on a number
            // of phones the audio driver turns that conversion into loud, clipped static. Without it those files are played at 16-bit
            // by the standard path, which works on every device.
            // The equalizer sits in the audio chain. While it is switched off it takes no part, so the audio is untouched.
            val ownFlac = AthanaEngine.enabled(app)
            val ownOut = AthanaEngine.outEnabled(app)
            AthanaEngine.startedFlac = ownFlac
            AthanaEngine.startedOut = ownOut
            android.util.Log.i("Athana", "Own audio output switch is " + (if (ownOut) "ON" else "OFF") + " (read when the player started)")
            android.util.Log.i("Athana", "Own FLAC decoder switch is " + (if (ownFlac) "ON" else "OFF") + " (read when the player started)")
            val renderers = object : DefaultRenderersFactory(app) {
                // With Athana's own FLAC decoder switched on, its renderer goes first, so it is the one chosen for FLAC songs.
                // Everything it does not take (other formats, more than 24 bits) goes to ExoPlayer's usual renderer.
                override fun buildAudioRenderers(
                    context: Context,
                    extensionRendererMode: Int,
                    mediaCodecSelector: MediaCodecSelector,
                    enableDecoderFallback: Boolean,
                    audioSink: AudioSink,
                    eventHandler: Handler,
                    eventListener: AudioRendererEventListener,
                    out: ArrayList<Renderer>
                ) {
                    super.buildAudioRenderers(context, extensionRendererMode, mediaCodecSelector, enableDecoderFallback, audioSink, eventHandler, eventListener, out)
                    if (ownFlac) out.add(0, AthanaAudioRenderer(eventHandler, eventListener, audioSink))
                }

                override fun buildAudioSink(context: Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink? {
                    val standard = DefaultAudioSink.Builder(context)
                        .setEnableFloatOutput(enableFloatOutput)
                        .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                        .setAudioProcessors(arrayOf<AudioProcessor>(EqProcessor()))
                        .build()
                    // With Athana's own output switched on, it takes songs that need no processing and sends them straight to the
                    // device at their real bit depth. Everything else (equalizer, tempo, other formats) still uses the standard sink.
                    return if (ownOut) AthanaAudioSink(app, standard) else standard
                }
            }.setEnableDecoderFallback(true)
            val attrs = AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build()
            val p = ExoPlayer.Builder(app, renderers)
                .setAudioAttributes(attrs, true)       // pause for calls, resume afterwards
                .setHandleAudioBecomingNoisy(true)     // pause when headphones are unplugged
                .setWakeMode(C.WAKE_MODE_LOCAL)
                .build()
            // The safety net: errors from Athana's own code are counted, and a crash inside it is remembered (see AthanaEngine.trip).
            p.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    if (!AthanaEngine.startedFlac && !AthanaEngine.startedOut) return
                    val trace = android.util.Log.getStackTraceString(error)
                    if (trace.contains("com.athana.lossless.Athana") || trace.contains("com.athana.lossless.EqCore")) AthanaEngine.failure(app, error.errorCodeName)
                }
            })
            if (!crashGuard) {
                crashGuard = true
                val previous = Thread.getDefaultUncaughtExceptionHandler()
                Thread.setDefaultUncaughtExceptionHandler(object : Thread.UncaughtExceptionHandler {
                    override fun uncaughtException(t: Thread, e: Throwable) {
                        try {
                            if ((AthanaEngine.startedFlac || AthanaEngine.startedOut) && android.util.Log.getStackTraceString(e).contains("com.athana.lossless.Athana")) {
                                AthanaEngine.trip(app, e.javaClass.simpleName)
                            }
                        } catch (_: Throwable) { }
                        previous?.uncaughtException(t, e)
                    }
                })
            }
            player = p
            return p
        }
    }
}

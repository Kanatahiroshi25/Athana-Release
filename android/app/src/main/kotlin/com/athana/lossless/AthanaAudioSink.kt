package com.athana.lossless

import android.annotation.SuppressLint
import android.media.AudioAttributes as PlatformAttributes
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat as PlatformFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Build
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Athana's own audio output.
 *
 * It writes the decoded PCM straight to an Android AudioTrack, at the bit depth the song really has (16, 24 or 32 bit), where the
 * standard output turns 24 and 32-bit songs into 16-bit first. It keeps its own count of the frames that have been played, so the
 * position that drives the progress bar and the lyrics comes from Athana's own clock.
 *
 * The equalizer, mixer, crossfeed and loudness normalisation run here too, with the same code as the standard chain ([EqCore]), but
 * they keep the song's bit depth: a 24-bit song stays 24-bit all the way to the device. With all of them off the bytes go through
 * untouched. Tempo is the one thing that still needs the standard chain, so while tempo is not 1x, and for anything that is not plain
 * 1 or 2 channel PCM, and whenever the device refuses the track, the song goes through the standard output (the one every earlier
 * version used). Everything that is not about the data itself (volume, session id, play and pause) is forwarded to the standard
 * output as well, so it is always ready to take over.
 */
@OptIn(UnstableApi::class)
@SuppressLint("NewApi")
class AthanaAudioSink(private val app: Context, private val standard: AudioSink) : ForwardingAudioSink(standard) {
    private var routeOwn = false          // the current stream goes through the code below
    private var track: AudioTrack? = null
    private var rate = 44100
    private var channels = 2
    private var enc = C.ENCODING_PCM_16BIT
    private var frameBytes = 4          // bytes per frame as it arrives from the player
    private var outFrame = 4              // bytes per frame as it is given to the AudioTrack
    private var floatOut = false          // Android 6 to 11: 24 and 32-bit songs go to the track as 32-bit float (exact for 24-bit)

    private var sessionId = C.AUDIO_SESSION_ID_UNSET
    private var vol = 1f
    private var playing = false           // ExoPlayer asked for play (not pause)
    private var trackStarted = false      // AudioTrack.play() was called since the last flush or pause
    private var handledEos = false

    private var bpAttrs: PlatformAttributes? = null       // set while Android's bit-perfect mixer is requested for this track
    private var bpDevice: AudioDeviceInfo? = null

    private val core = EqCore()           // the equalizer and mixer, used while any of them is on
    private var scratch: ByteBuffer? = null
    private var pendingOut: ByteBuffer? = null   // shaped audio that is still waiting for room in the track

    private var written = 0L              // frames given to the AudioTrack since the last flush
    private var anchored = false
    private var reanchor = false
    private var anchorUs = 0L             // the song time of the frame at index anchorFrame
    private var anchorFrame = 0L

    private var headWraps = 0L
    private var lastHead = 0L

    // ---- configuration -----------------------------------------------------------------------------------------------------

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        val speed = standard.playbackParameters.speed
        val wantOwn = canOwn(inputFormat) && speed == 1f
        if (!wantOwn) AthanaEngine.outNote = if (canOwn(inputFormat)) "tempo is not 1x, so the standard output is used" else whyNot(inputFormat)
        if (wantOwn) {
            if (track != null && inputFormat.sampleRate == rate && inputFormat.channelCount == channels && inputFormat.pcmEncoding == enc) {
                // Same format as the song before: keep the track, so the songs follow each other without a gap.
                routeOwn = true
                handledEos = false
                pendingOut = null
                core.configure(rate, channels, enc)
                return
            }
            releaseOwn()
            standard.reset()
            if (buildTrack(inputFormat)) {
                routeOwn = true
                handledEos = false
                core.configure(rate, channels, enc)
                if (playing) ownPlay()
                return
            }
        } else {
            releaseOwn()
        }
        routeOwn = false
        AthanaEngine.outDesc = ""
        super.configure(inputFormat, specifiedBufferSize, outputChannels)
        if (playing) super.play()
    }

    private fun canOwn(f: Format): Boolean {
        if (AthanaEngine.tripped) return false
        if (f.sampleMimeType != MimeTypes.AUDIO_RAW) return false
        if (f.channelCount != 1 && f.channelCount != 2) return false
        if (f.sampleRate <= 0) return false
        if (Build.VERSION.SDK_INT < 23) return false      // AudioTrack.Builder
        val e = f.pcmEncoding
        // 16-bit always. 24 and 32-bit: packed on Android 12 and later, 32-bit float (which holds 24 bits exactly) before that.
        return e == C.ENCODING_PCM_16BIT || e == C.ENCODING_PCM_24BIT || e == C.ENCODING_PCM_32BIT
    }

    private fun whyNot(f: Format): String {
        if (AthanaEngine.tripped) return "it was switched off automatically after repeated errors"
        if (f.sampleMimeType != MimeTypes.AUDIO_RAW) return "this song does not reach the output as plain PCM"
        if (f.channelCount != 1 && f.channelCount != 2) return "it has more than 2 channels"
        if (Build.VERSION.SDK_INT < 23) return "this Android version is too old"
        return "this song's sample format is not supported by the Athana output"
    }

    private fun buildTrack(f: Format): Boolean {
        try {
            val r = f.sampleRate
            val ch = f.channelCount
            val mask = if (ch == 1) PlatformFormat.CHANNEL_OUT_MONO else PlatformFormat.CHANNEL_OUT_STEREO
            val bytes: Int          // bytes per sample as it arrives
            val outBytes: Int       // bytes per sample as it is given to the track
            val platformEnc: Int
            val asFloat = Build.VERSION.SDK_INT < 31 && (f.pcmEncoding == C.ENCODING_PCM_24BIT || f.pcmEncoding == C.ENCODING_PCM_32BIT)
            when (f.pcmEncoding) {
                C.ENCODING_PCM_16BIT -> { bytes = 2; platformEnc = PlatformFormat.ENCODING_PCM_16BIT }
                C.ENCODING_PCM_24BIT -> { bytes = 3; platformEnc = if (asFloat) PlatformFormat.ENCODING_PCM_FLOAT else PlatformFormat.ENCODING_PCM_24BIT_PACKED }
                C.ENCODING_PCM_32BIT -> { bytes = 4; platformEnc = if (asFloat) PlatformFormat.ENCODING_PCM_FLOAT else PlatformFormat.ENCODING_PCM_32BIT }
                else -> return false
            }
            outBytes = if (asFloat) 4 else bytes
            val frame = ch * outBytes
            val min = AudioTrack.getMinBufferSize(r, mask, platformEnc)
            if (min <= 0) { AthanaEngine.outNote = "the phone does not take ${bytes * 8}-bit at $r Hz"; Log.i("Athana", "Own audio output: the device does not take ${bytes * 8}-bit${if (asFloat) " (float)" else ""} at $r Hz, using the standard output"); return false }
            // About 0.4 s of audio, never less than twice the smallest size the device allows (and a whole number of frames).
            var size = maxOf(min * 2, (r * frame * 0.4).toInt())
            size -= size % frame
            val attrs = PlatformAttributes.Builder()
                .setUsage(PlatformAttributes.USAGE_MEDIA)
                .setContentType(PlatformAttributes.CONTENT_TYPE_MUSIC)
                .build()
            // On Android 14 and later, a USB DAC can be given the song with no mixing and no resampling (bit-perfect mixer).
            val bp = tryBitPerfect(attrs, r, platformEnc, mask)
            val fmt = PlatformFormat.Builder().setSampleRate(r).setEncoding(platformEnc).setChannelMask(mask).build()
            val b = AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(fmt)
                .setBufferSizeInBytes(size)
                .setTransferMode(AudioTrack.MODE_STREAM)
            if (sessionId != C.AUDIO_SESSION_ID_UNSET) b.setSessionId(sessionId)
            val t = b.build()
            if (t.state != AudioTrack.STATE_INITIALIZED) {
                t.release()
                clearBitPerfect()
                AthanaEngine.outNote = "the audio track could not be opened"
                Log.i("Athana", "Own audio output: the track could not be opened, using the standard output")
                return false
            }
            t.setVolume(vol)
            track = t
            rate = r
            channels = ch
            enc = f.pcmEncoding
            frameBytes = ch * bytes
            outFrame = frame
            floatOut = asFloat
            written = 0
            anchored = false
            reanchor = false
            headWraps = 0
            lastHead = 0
            trackStarted = false
            // A float track holds 24 bits of the song exactly; a 32-bit song loses its lowest 8 bits there.
            AthanaEngine.outDesc = if (asFloat) "${minOf(24, bytes * 8)}-bit (float)" else "${bytes * 8}-bit"
            AthanaEngine.outNote = ""
            AthanaEngine.bitPerfect = bp
            Log.i("Athana", "Own audio output started: ${bytes * 8} bit${if (asFloat) " as float" else ""}, $ch ch, $r Hz, buffer ${size * 1000L / (r.toLong() * frame)} ms" + (if (bp) ", bit-perfect mixer" else ""))
            return true
        } catch (e: Throwable) {
            Log.w("Athana", "Own audio output could not start: $e")
            AthanaEngine.outNote = "the audio track could not start"
            clearBitPerfect()
            return false
        }
    }

    /**
     * Asks Android for its bit-perfect mixer for the device this song will play on, when the user switched that on. It only exists on
     * Android 14 or later, and only some outputs (mostly USB DACs) offer it, and only for the formats they list. Returns true when
     * it was granted for exactly this sample rate, bit depth and channel layout. Anything else leaves the normal mixer in place.
     */
    private fun tryBitPerfect(attrs: PlatformAttributes, rate: Int, enc: Int, mask: Int): Boolean {
        clearBitPerfect()
        AthanaEngine.bpNote = ""
        if (!AthanaEngine.bitPerfectEnabled(app)) return false
        if (Build.VERSION.SDK_INT < 34) { AthanaEngine.bpNote = "needs Android 14 or later"; return false }
        AthanaEngine.bpNote = "this output (speaker or Bluetooth) has no bit-perfect mixer. It is for USB DACs"
        try {
            val am = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            for (d in am.getAudioDevicesForAttributes(attrs)) {
                val supported = am.getSupportedMixerAttributes(d)
                if (supported.isEmpty()) {
                    Log.i("Athana", "Bit-perfect mixer: ${d.productName} offers none")
                    continue
                }
                for (m in supported) {
                    if (m.mixerBehavior != AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT) continue
                    val f = m.format
                    Log.i("Athana", "Bit-perfect mixer offered by ${d.productName}: ${f.sampleRate} Hz, encoding ${f.encoding}, mask ${f.channelMask}")
                    AthanaEngine.bpNote = "the connected output does not offer this song's format (${rate} Hz, ${if (enc == PlatformFormat.ENCODING_PCM_16BIT) 16 else if (enc == PlatformFormat.ENCODING_PCM_24BIT_PACKED) 24 else 32}-bit)"
                    if (f.sampleRate == rate && f.encoding == enc && f.channelMask == mask && am.setPreferredMixerAttributes(attrs, d, m)) {
                        AthanaEngine.bpNote = ""
                        bpAttrs = attrs
                        bpDevice = d
                        return true
                    }
                }
            }
        } catch (e: Throwable) {
            Log.w("Athana", "Bit-perfect mixer could not be requested: $e")
        }
        return false
    }

    private fun clearBitPerfect() {
        AthanaEngine.bitPerfect = false
        val a = bpAttrs
        val d = bpDevice
        bpAttrs = null
        bpDevice = null
        if (a != null && d != null && Build.VERSION.SDK_INT >= 34) {
            try {
                (app.getSystemService(Context.AUDIO_SERVICE) as AudioManager).clearPreferredMixerAttributes(a, d)
            } catch (_: Throwable) { }
        }
    }

    private fun releaseOwn() {
        val t = track
        track = null
        trackStarted = false
        written = 0
        anchored = false
        reanchor = false
        headWraps = 0
        lastHead = 0
        pendingOut = null
        AthanaEngine.outDesc = ""
        clearBitPerfect()
        if (t != null) {
            try { t.pause() } catch (_: Throwable) { }
            try { t.flush() } catch (_: Throwable) { }
            try { t.release() } catch (_: Throwable) { }
        }
    }

    // ---- the data ----------------------------------------------------------------------------------------------------------

    override fun handleBuffer(buffer: ByteBuffer, presentationTimeUs: Long, encodedAccessUnitCount: Int): Boolean {
        if (!routeOwn) return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)
        val t = track ?: return true
        handledEos = false
        // A piece that was already shaped is still waiting for room in the track: finish it first. (The player calls again with the
        // same buffer, which was used up when it was shaped.)
        val waiting = pendingOut
        if (waiting != null) {
            if (!writeOut(t, waiting)) return false
            pendingOut = null
            return true
        }
        val start = buffer.position()
        val size = buffer.limit() - start
        if (size <= 0) return true
        if (!anchored || reanchor) {
            anchorUs = presentationTimeUs
            anchorFrame = written
            anchored = true
            reanchor = false
        }
        if (EqState.active || floatOut) {
            // Equalizer, mixer or normalisation on: shape the audio, at the same bit depth it came in.
            // On a float track the audio is also converted here (24-bit to float is exact, with nothing added).
            val frames = size / frameBytes
            val need = frames * outFrame
            var sc = scratch
            if (sc == null || sc.capacity() < need) {
                sc = ByteBuffer.allocateDirect(need + 8192).order(ByteOrder.nativeOrder())
                scratch = sc
            }
            sc!!.clear()
            if (EqState.active) core.process(buffer, frames, sc, if (floatOut) 0 else frameBytes / channels * 8)
            else convertToFloat(buffer, frames * channels, sc)
            sc.flip()
            buffer.position(buffer.limit())
            if (writeOut(t, sc)) return true
            pendingOut = sc
            return false
        }
        return writeOut(t, buffer)
    }

    /** Plain conversion of 24 or 32-bit integer samples to float, for the float track. No filter, gain or dither. */
    private fun convertToFloat(src: ByteBuffer, samples: Int, out: ByteBuffer) {
        if (enc == C.ENCODING_PCM_24BIT) {
            for (i in 0 until samples) {
                val lo = src.get().toInt() and 0xFF
                val mid = src.get().toInt() and 0xFF
                val hi = src.get().toInt()
                out.putFloat(((hi shl 16) or (mid shl 8) or lo) / 8388608f)
            }
        } else {
            for (i in 0 until samples) out.putFloat((src.int / 2147483648.0).toFloat())
        }
    }

    /** Gives as much of [b] as the track has room for. Returns true when all of it is written (or dropped because the track broke). */
    private fun writeOut(t: AudioTrack, b: ByteBuffer): Boolean {
        val start = b.position()
        val size = b.limit() - start
        if (size <= 0) return true
        val n = try {
            t.write(b, size, AudioTrack.WRITE_NON_BLOCKING)
        } catch (e: Throwable) {
            Log.w("Athana", "Own audio output write failed: $e")
            -1
        }
        if (n < 0) {
            // The track broke (for example the device was unplugged). Drop this piece so the player carries on.
            b.position(b.limit())
            return true
        }
        b.position(start + n)
        written += n / outFrame
        ownStartIfNeeded()
        return !b.hasRemaining()
    }

    override fun playToEndOfStream() {
        if (!routeOwn) { super.playToEndOfStream(); return }
        handledEos = true
        ownStartIfNeeded()
    }

    override fun isEnded(): Boolean {
        if (!routeOwn) return super.isEnded()
        return track == null || (handledEos && !hasPendingData())
    }

    override fun hasPendingData(): Boolean {
        if (!routeOwn) return super.hasPendingData()
        return track != null && (pendingOut?.hasRemaining() == true || playedFrames() < written)
    }

    override fun handleDiscontinuity() {
        if (!routeOwn) { super.handleDiscontinuity(); return }
        reanchor = true
    }

    // ---- the clock ---------------------------------------------------------------------------------------------------------

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        if (!routeOwn) return super.getCurrentPositionUs(sourceEnded)
        if (track == null || !anchored) return AudioSink.CURRENT_POSITION_NOT_SET
        val played = playedFrames()
        return anchorUs + (played - anchorFrame) * 1_000_000L / rate
    }

    /** How many frames have really left through the speaker (or the cable) since the last flush. */
    private fun playedFrames(): Long {
        val t = track ?: return 0
        var total: Long
        try {
            val head = t.playbackHeadPosition.toLong() and 0xFFFFFFFFL
            if (head < lastHead - (1L shl 31)) headWraps += 1L shl 32      // the 32-bit counter went round
            lastHead = head
            total = head + headWraps
            if (playing && trackStarted) {
                // The timestamp knows exactly which frame is sounding now, so it also covers the delay of Bluetooth and DACs.
                val ts = AudioTimestamp()
                if (t.getTimestamp(ts)) {
                    val elapsedNs = System.nanoTime() - ts.nanoTime
                    if (elapsedNs in 0..2_000_000_000L) {
                        val viaTs = ts.framePosition + elapsedNs * rate / 1_000_000_000L
                        if (viaTs > 0) total = viaTs
                    }
                }
            }
        } catch (_: Throwable) {
            total = 0
        }
        return minOf(total, written)
    }

    // ---- play, pause, flush ------------------------------------------------------------------------------------------------

    override fun play() {
        playing = true
        super.play()
        if (routeOwn) ownPlay()
    }

    override fun pause() {
        playing = false
        super.pause()
        if (routeOwn) {
            val t = track
            if (t != null && trackStarted) {
                try { t.pause() } catch (_: Throwable) { }
                trackStarted = false
            }
        }
    }

    private fun ownPlay() = ownStartIfNeeded()

    private fun ownStartIfNeeded() {
        val t = track ?: return
        if (playing && !trackStarted && written > 0) {
            try {
                t.play()
                trackStarted = true
            } catch (e: Throwable) {
                Log.w("Athana", "Own audio output could not play: $e")
            }
        }
    }

    override fun flush() {
        if (!routeOwn) { super.flush(); return }
        val t = track ?: return
        try { t.pause() } catch (_: Throwable) { }
        try { t.flush() } catch (_: Throwable) { }
        trackStarted = false
        written = 0
        headWraps = 0
        lastHead = 0
        anchored = false
        reanchor = false
        handledEos = false
        pendingOut = null
        core.flush()
    }

    override fun reset() {
        releaseOwn()
        routeOwn = false
        super.reset()
    }

    override fun setVolume(volume: Float) {
        vol = volume
        super.setVolume(volume)
        try { track?.setVolume(volume) } catch (_: Throwable) { }
    }

    override fun setAudioSessionId(audioSessionId: Int) {
        sessionId = audioSessionId
        super.setAudioSessionId(audioSessionId)
    }
}

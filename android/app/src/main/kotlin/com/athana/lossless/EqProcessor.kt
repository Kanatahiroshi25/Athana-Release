package com.athana.lossless

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sign
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tanh

/** The equalizer settings: written by the screen, read by the audio thread. */
object EqState {
    /** The ten band centres in Hz, the same as the web version. */
    val freqs = doubleArrayOf(31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0)

    @Volatile var on = false
    @Volatile var pre = 0f                       // dB, already including any clipping protection
    @Volatile var gains = FloatArray(10)         // dB per band
    @Volatile var version = 0                    // goes up whenever something changed
    @Volatile var normOn = false                 // loudness normalisation switched on
    @Volatile var normGain = 0f                  // dB applied to the current song by normalisation

    /** The processor only takes part in the audio chain while the equalizer or normalisation is on. */
    val active: Boolean get() = on || normOn || mixOn

    // The mixer: balance, stereo expand, mono and volume
    @Volatile var mixOn = false                  // any mixer knob moved away from its centre (kept until Reset)
    @Volatile var bal = 0f                       // -1 (left only) .. +1 (right only)
    @Volatile var wide = 0f                      // 0 .. 1, how much the stereo field is widened
    @Volatile var mono = false
    @Volatile var vol = 1f                       // linear, 1 = untouched
    @Volatile var cross = 0f                     // crossfeed for headphones, 0 .. 1

    /** Stores new settings. Returns true when the on/off switch itself changed (the player must then be re-prepared). */
    @Synchronized
    fun set(newOn: Boolean, newPre: Float, newGains: FloatArray): Boolean {
        val before = active
        pre = newPre
        gains = if (newGains.size == 10) newGains.copyOf() else FloatArray(10)
        on = newOn
        version++
        return before != active
    }

    /** Stores the mixer knobs. Returns true when the chain has to be rebuilt. */
    @Synchronized
    fun setMix(active: Boolean, balance: Float, expand: Float, toMono: Boolean, volume: Float, crossfeed: Float): Boolean {
        val before = this.active
        mixOn = active
        bal = balance.coerceIn(-1f, 1f)
        wide = expand.coerceIn(0f, 1f)
        mono = toMono
        vol = volume.coerceIn(0f, 2f)
        cross = crossfeed.coerceIn(0f, 1f)
        version++
        return before != this.active
    }

    /** Switches normalisation on or off. Returns true when the chain has to be rebuilt. */
    @Synchronized
    fun setNorm(newOn: Boolean, gainDb: Float): Boolean {
        val before = active
        normOn = newOn
        normGain = gainDb
        version++
        return before != active
    }

    /** A new gain for the current song (no rebuild needed, the processor glides to it). */
    @Synchronized
    fun updateNormGain(gainDb: Float) {
        normGain = gainDb
        version++
    }
}

/**
 * The sound shaping itself: ten peaking filters (Q 1.1, like the web version) and a preamp, then the mixer (crossfeed, stereo expand,
 * mono, balance and volume trim). It knows nothing about Media3, so both the standard audio chain ([EqProcessor], always 16-bit out)
 * and Athana's own audio output (the same bit depth out as in) use exactly the same code.
 */
class EqCore {
    private var channels = 2
    private var rate = 44100
    private var enc = C.ENCODING_PCM_16BIT

    private val b0 = DoubleArray(10)
    private val b1 = DoubleArray(10)
    private val b2 = DoubleArray(10)
    private val a1 = DoubleArray(10)
    private val a2 = DoubleArray(10)
    private val live = BooleanArray(10)
    private var z1 = Array(2) { DoubleArray(10) }
    private var z2 = Array(2) { DoubleArray(10) }
    private var seen = -1
    private var preGain = 1.0       // where the gain should be
    private var curGain = 1.0       // where it is now (it glides, so a change never clicks)
    private var primed = false
    private var balL = 1.0
    private var balR = 1.0
    private var wide = 0.0
    private var toMono = false
    private var volTarget = 1.0
    private var curVol = 1.0
    private var fr = DoubleArray(2)
    // Crossfeed: a little of each side, softened and slightly late, is blended into the other ear (like speakers in a room)
    private var xfG = 0.0
    private var xfNorm = 1.0
    private var xfA = 0.1
    private var xfD = 12
    private var xfL = DoubleArray(12)
    private var xfR = DoubleArray(12)
    private var xfPos = 0
    private var xfLpL = 0.0
    private var xfLpR = 0.0
    private var wideM = 1.0      // Stereo Expand: how much of the centre is kept
    private var wideS = 1.0      // and how much the side is raised
    private var seed = 88172645463325252L

    /** Prepares for a new stream. [enc] is one of the C.ENCODING_PCM_* values for 16, 24, 32-bit integer or float input. */
    fun configure(sampleRate: Int, channelCount: Int, encoding: Int) {
        channels = max(1, channelCount)
        rate = sampleRate
        enc = encoding
        fr = DoubleArray(channels)
        xfD = max(1, (rate * 0.00025).roundToInt())      // 0.25 ms, about the extra distance to the far ear
        xfL = DoubleArray(xfD)
        xfR = DoubleArray(xfD)
        xfPos = 0
        xfLpL = 0.0
        xfLpR = 0.0
        xfA = 1.0 - Math.exp(-2.0 * PI * 700.0 / rate)   // soften above 700 Hz, because the head shades the far ear
        z1 = Array(channels) { DoubleArray(10) }
        z2 = Array(channels) { DoubleArray(10) }
        seen = -1
        primed = false
    }

    /** Forgets what was playing (after a seek), so nothing rings on into the new spot. */
    fun flush() {
        xfL.fill(0.0); xfR.fill(0.0); xfLpL = 0.0; xfLpR = 0.0
        for (c in 0 until channels) {
            z1[c].fill(0.0)
            z2[c].fill(0.0)
        }
    }

    private fun refresh() {
        val v = EqState.version
        if (v == seen) return
        seen = v
        val g = EqState.gains
        val eq = EqState.on
        val norm = if (EqState.normOn) EqState.normGain.toDouble() else 0.0
        preGain = 10.0.pow(((if (eq) EqState.pre.toDouble() else 0.0) + norm) / 20.0)
        balL = 1.0 - max(0f, EqState.bal).toDouble()
        balR = 1.0 + min(0f, EqState.bal).toDouble()
        wide = EqState.wide.toDouble()
        // Stereo Expand = cross-feeding a phase-inverted copy of each channel into the other: L' = L - k*R, R' = R - k*L.
        // That is the same as keeping (1-k) of the centre and raising the side to (1+k), then a level trim so it does not get quieter.
        xfG = 0.5 * EqState.cross
        xfNorm = 1.0 / (1.0 + 0.6 * xfG)
        val k = 0.8 * wide
        val trim = 1.0 / sqrt(1.0 + k * k)
        wideM = (1.0 - k) * trim
        wideS = (1.0 + k) * trim
        toMono = EqState.mono
        volTarget = EqState.vol.toDouble()
        if (!primed) { curGain = preGain; curVol = volTarget; primed = true }
        for (i in 0 until 10) {
            val f = EqState.freqs[i]
            val db = g[i].toDouble()
            if (!eq || abs(db) < 0.05 || f >= rate * 0.45) {
                live[i] = false
                continue
            }
            val amp = 10.0.pow(db / 40.0)
            val w0 = 2.0 * PI * f / rate
            val alpha = sin(w0) / (2.0 * 1.1)
            val a0 = 1.0 + alpha / amp
            b0[i] = (1.0 + alpha * amp) / a0
            b1[i] = (-2.0 * cos(w0)) / a0
            b2[i] = (1.0 - alpha * amp) / a0
            a1[i] = (-2.0 * cos(w0)) / a0
            a2[i] = (1.0 - alpha / amp) / a0
            live[i] = true
        }
    }

    /**
     * Reads [frames] frames from [src] and writes the shaped audio to [out] as [outBits] (16, 24 or 32) bit little-endian integers, or as 32-bit float when [outBits] is 0.
     * Both buffers must be in the phone's native (little-endian) byte order, as Media3's buffers are.
     */
    fun process(src: ByteBuffer, frames: Int, out: ByteBuffer, outBits: Int) {
        if (frames <= 0) return
        refresh()
        for (f in 0 until frames) {
            curGain += (preGain - curGain) * 0.0004     // about 50 ms to glide to a new gain
            curVol += (volTarget - curVol) * 0.0004
            for (c in 0 until channels) {
                var x: Double = when (enc) {
                    C.ENCODING_PCM_16BIT -> src.short / 32768.0
                    C.ENCODING_PCM_24BIT -> {
                        val lo = src.get().toInt() and 0xFF
                        val mid = src.get().toInt() and 0xFF
                        val hi = src.get().toInt()
                        ((hi shl 16) or (mid shl 8) or lo) / 8388608.0
                    }
                    C.ENCODING_PCM_32BIT -> src.int / 2147483648.0
                    else -> src.float.toDouble()
                }
                x *= curGain
                val s1 = z1[c]
                val s2 = z2[c]
                for (i in 0 until 10) {
                    if (!live[i]) continue
                    val y = b0[i] * x + s1[i]
                    s1[i] = b1[i] * x - a1[i] * y + s2[i]
                    s2[i] = b2[i] * x - a2[i] * y
                    x = y
                }
                fr[c] = x
            }
            // The mixer works on the finished stereo signal.
            if (channels == 2) {
                var l = fr[0]
                var r = fr[1]
                if (xfG > 0.0005) {
                    val fromR = xfR[xfPos]     // the right channel, 0.25 ms ago
                    val fromL = xfL[xfPos]
                    xfR[xfPos] = r
                    xfL[xfPos] = l
                    xfPos = (xfPos + 1) % xfD
                    xfLpL += xfA * (fromR - xfLpL)
                    xfLpR += xfA * (fromL - xfLpR)
                    l = (l + xfG * xfLpL) * xfNorm
                    r = (r + xfG * xfLpR) * xfNorm
                }
                if (toMono) {
                    val m = (l + r) * 0.5
                    l = m
                    r = m
                } else if (wide > 0.001) {
                    val m = (l + r) * 0.5
                    val sd = (l - r) * 0.5
                    l = m * wideM + sd * wideS
                    r = m * wideM - sd * wideS
                }
                fr[0] = l * balL
                fr[1] = r * balR
            } else if (toMono && channels > 2) {
                var sum = 0.0
                for (c in 0 until channels) sum += fr[c]
                val m = sum / channels
                for (c in 0 until channels) fr[c] = m
            }
            for (c in 0 until channels) {
                val y = limit(fr[c] * curVol)
                when (outBits) {
                    16 -> out.putShort(toInt16(y))
                    24 -> {
                        val v = min(8388607, max(-8388608, (y * 8388607.0).roundToInt()))
                        out.put(v.toByte())
                        out.put((v shr 8).toByte())
                        out.put((v shr 16).toByte())
                    }
                    0 -> out.putFloat(y.toFloat())
                    else -> out.putInt(min(2147483647L, max(-2147483648L, Math.round(y * 2147483647.0))).toInt())
                }
            }
        }
    }

    private fun rnd(): Double {
        seed = seed * 6364136223846793005L + 1442695040888963407L
        return ((seed ushr 40).toInt() and 0xFFFF) / 65536.0
    }

    /** A soft limit instead of a harsh clip. */
    private fun limit(x: Double): Double {
        val ax = abs(x)
        return if (ax > 0.97) sign(x) * (0.97 + 0.03 * tanh((ax - 0.97) / 0.03)) else x
    }

    private fun toInt16(x: Double): Short {
        val dither = (rnd() - rnd()) / 32768.0                                    // one step of triangular dither
        val v = ((x + dither) * 32767.0).roundToInt()
        return min(32767, max(-32768, v)).toShort()
    }
}

/**
 * The equalizer and mixer as a Media3 audio processor, for the standard audio chain.
 * While the equalizer is switched off the processor is not part of the chain at all, so the audio is untouched.
 * The output is always 16-bit, which is what the standard chain uses.
 */
@OptIn(UnstableApi::class)
class EqProcessor : BaseAudioProcessor() {
    private val core = EqCore()
    private var channels = 2
    private var enc = C.ENCODING_PCM_16BIT

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (!EqState.active) return AudioProcessor.AudioFormat.NOT_SET
        val e = inputAudioFormat.encoding
        if (e != C.ENCODING_PCM_16BIT && e != C.ENCODING_PCM_24BIT && e != C.ENCODING_PCM_32BIT && e != C.ENCODING_PCM_FLOAT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        channels = max(1, inputAudioFormat.channelCount)
        enc = e
        core.configure(inputAudioFormat.sampleRate, channels, e)
        return AudioProcessor.AudioFormat(inputAudioFormat.sampleRate, channels, C.ENCODING_PCM_16BIT)
    }

    override fun onFlush() {
        core.flush()
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val bytes = when (enc) {
            C.ENCODING_PCM_16BIT -> 2
            C.ENCODING_PCM_24BIT -> 3
            else -> 4
        }
        val frames = inputBuffer.remaining() / (bytes * channels)
        if (frames <= 0) return
        val out = replaceOutputBuffer(frames * channels * 2)
        core.process(inputBuffer, frames, out, 16)
        out.flip()
    }
}

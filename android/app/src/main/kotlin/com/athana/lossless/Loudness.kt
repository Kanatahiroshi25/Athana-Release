package com.athana.lossless

import android.content.Context
import android.media.MediaCodec
import android.media.MediaDataSource
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSpec
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.tan

/** How loud a song is (LUFS, ITU-R BS.1770 with gating) and its highest sample (dBFS). */
class LoudnessResult(val lufs: Double, val peakDb: Double)

/** Measures loudness the way streaming services do: K-weighting, 400 ms blocks, absolute and relative gate. */
class LoudnessMeter(private val rate: Int, private val channels: Int) {
    private class Bq(val b0: Double, val b1: Double, val b2: Double, val a1: Double, val a2: Double) {
        var z1 = 0.0
        var z2 = 0.0
        fun run(x: Double): Double {
            val y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private val shelf: Array<Bq>
    private val high: Array<Bq>
    private val sub = ArrayList<Double>()      // loudness energy of each 100 ms, summed over channels
    private val step = max(1, rate / 10)
    private var acc = DoubleArray(max(1, channels))
    private var count = 0
    private var peak = 0.0

    init {
        // stage 1: the head-shelf, stage 2: the 38 Hz high-pass (coefficients from the standard, for any sample rate)
        val f1 = 1681.974450955533; val g = 3.999843853973347; val q1 = 0.7071752369554196
        val k1 = tan(PI * f1 / rate); val vh = 10.0.pow(g / 20.0); val vb = vh.pow(0.4996667741545416)
        val a0 = 1.0 + k1 / q1 + k1 * k1
        val s1 = { Bq((vh + vb * k1 / q1 + k1 * k1) / a0, 2.0 * (k1 * k1 - vh) / a0, (vh - vb * k1 / q1 + k1 * k1) / a0, 2.0 * (k1 * k1 - 1.0) / a0, (1.0 - k1 / q1 + k1 * k1) / a0) }
        val f2 = 38.13547087602444; val q2 = 0.5003270373238773
        val k2 = tan(PI * f2 / rate)
        val c0 = 1.0 + k2 / q2 + k2 * k2
        val s2 = { Bq(1.0, -2.0, 1.0, 2.0 * (k2 * k2 - 1.0) / c0, (1.0 - k2 / q2 + k2 * k2) / c0) }
        shelf = Array(max(1, channels)) { s1() }
        high = Array(max(1, channels)) { s2() }
    }

    /** [x] holds [frames] frames of interleaved samples in the range -1..1. */
    fun add(x: FloatArray, frames: Int) {
        for (f in 0 until frames) {
            for (c in 0 until channels) {
                val v = x[f * channels + c].toDouble()
                val a = abs(v)
                if (a > peak) peak = a
                val w = high[c].run(shelf[c].run(v))
                acc[c] += w * w
            }
            count++
            if (count >= step) {
                var e = 0.0
                for (c in 0 until channels) { e += acc[c] / count; acc[c] = 0.0 }
                sub.add(e)
                count = 0
            }
        }
    }

    fun result(): LoudnessResult? {
        val n = sub.size - 3
        if (n <= 0) return null
        val blocks = DoubleArray(n) { (sub[it] + sub[it + 1] + sub[it + 2] + sub[it + 3]) / 4.0 }
        fun lu(e: Double) = -0.691 + 10.0 * log10(e)
        val above = blocks.filter { it > 0.0 && lu(it) > -70.0 }
        if (above.isEmpty()) return null
        val gate = lu(above.average()) - 10.0
        val kept = above.filter { lu(it) > gate }
        if (kept.isEmpty()) return null
        val peakDb = if (peak > 0.0) 20.0 * log10(peak) else -120.0
        return LoudnessResult(lu(kept.average()), peakDb)
    }
}

/** Reads a song to the end in the background and measures it. Works for everything Android can decode, and for AIFF. */
@OptIn(UnstableApi::class)
object LoudnessAnalyzer {
    private const val MAX_SECONDS = 12 * 60

    fun measure(ctx: Context, uri: Uri, aiff: Boolean, cancelled: () -> Boolean): LoudnessResult? {
        val ex = MediaExtractor()
        var src: AiffMediaSource? = null
        var codec: MediaCodec? = null
        try {
            if (aiff) {
                src = AiffMediaSource(ctx, uri)
                ex.setDataSource(src)
            } else {
                ex.setDataSource(ctx, uri, null)
            }
            var track = -1
            var fmt: MediaFormat? = null
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                if ((f.getString(MediaFormat.KEY_MIME) ?: "").startsWith("audio/")) { track = i; fmt = f; break }
            }
            if (track < 0 || fmt == null) return null
            ex.selectTrack(track)
            codec = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(fmt, null, null, 0)
            codec.start()

            var rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var ch = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var enc = 2 // AudioFormat.ENCODING_PCM_16BIT
            var meter = LoudnessMeter(rate, ch)
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var seconds = 0.0
            var tmp = FloatArray(0)
            var idle = 0
            while (!outputDone && !cancelled()) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(5000)
                    if (i >= 0) {
                        val buf = codec.getInputBuffer(i)!!
                        val n = ex.readSampleData(buf, 0)
                        if (n < 0 || seconds > MAX_SECONDS) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, n, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 5000)
                when {
                    o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val nf = codec.outputFormat
                        val nr = nf.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        val nc = nf.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        enc = if (nf.containsKey(MediaFormat.KEY_PCM_ENCODING)) nf.getInteger(MediaFormat.KEY_PCM_ENCODING) else 2
                        if (nr != rate || nc != ch) { rate = nr; ch = nc; meter = LoudnessMeter(rate, ch) }
                    }
                    o >= 0 -> {
                        idle = 0
                        val out = codec.getOutputBuffer(o)
                        if (out != null && info.size > 0) {
                            out.position(info.offset)
                            out.limit(info.offset + info.size)
                            out.order(ByteOrder.nativeOrder())
                            val frames: Int
                            if (enc == 4) { // float
                                val fb = out.asFloatBuffer()
                                val total = fb.remaining()
                                frames = total / ch
                                if (tmp.size < frames * ch) tmp = FloatArray(frames * ch)
                                fb.get(tmp, 0, frames * ch)
                            } else { // 16-bit
                                val sb = out.asShortBuffer()
                                val total = sb.remaining()
                                frames = total / ch
                                if (tmp.size < frames * ch) tmp = FloatArray(frames * ch)
                                for (k in 0 until frames * ch) tmp[k] = sb.get() / 32768f
                            }
                            meter.add(tmp, frames)
                            seconds += frames.toDouble() / rate
                        }
                        codec.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                    else -> { if (inputDone && ++idle > 400) outputDone = true }
                }
            }
            return if (cancelled()) null else meter.result()
        } catch (_: Exception) {
            return null
        } finally {
            try { codec?.stop() } catch (_: Exception) { }
            try { codec?.release() } catch (_: Exception) { }
            try { ex.release() } catch (_: Exception) { }
            try { src?.close() } catch (_: Exception) { }
        }
    }
}

/** Presents an AIFF file as WAV to MediaExtractor, using the same converter the player uses. */
@OptIn(UnstableApi::class)
internal class AiffMediaSource(private val ctx: Context, private val uri: Uri) : MediaDataSource() {
    private var ds: AiffWavDataSource? = null
    private var at = -1L
    private var size = -1L

    private fun open(pos: Long) {
        try { ds?.close() } catch (_: Exception) { }
        val d = AiffWavDataSource(ctx)
        val len = d.open(DataSpec(uri, pos, C.LENGTH_UNSET.toLong()))
        if (size < 0) size = if (len == C.LENGTH_UNSET.toLong()) -1L else pos + len
        ds = d
        at = pos
    }

    override fun readAt(position: Long, buffer: ByteArray, offset: Int, length: Int): Int {
        if (ds == null || at != position) open(position)
        val n = ds!!.read(buffer, offset, length)
        if (n <= 0) return -1
        at += n
        return n
    }

    override fun getSize(): Long {
        if (size < 0) open(0)
        return size
    }

    override fun close() {
        try { ds?.close() } catch (_: Exception) { }
        ds = null
    }
}

/** Keeps what was measured, so every song is measured only once. */
class LoudnessCache(ctx: Context) {
    private val sp = ctx.getSharedPreferences("athana_loudness", Context.MODE_PRIVATE)

    fun get(key: String): LoudnessResult? {
        val v = sp.getString(key, null) ?: return null
        val p = v.split(';')
        if (p.size != 2) return null
        val l = p[0].toDoubleOrNull() ?: return null
        val k = p[1].toDoubleOrNull() ?: return null
        return LoudnessResult(l, k)
    }

    fun put(key: String, r: LoudnessResult) {
        if (sp.all.size > 4000) sp.edit().clear().apply()   // a very large library: start over rather than grow without end
        sp.edit().putString(key, "${r.lufs};${r.peakDb}").apply()
    }
}

/** The gain that brings a song to the target without clipping: -12..+6 dB, never above what the peak allows. */
fun normGainFor(r: LoudnessResult, target: Double): Float {
    val g = min(max(-12.0, min(6.0, target - r.lufs)), -r.peakDb)
    return g.toFloat()
}

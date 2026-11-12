package com.athana.lossless

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** Everything "Analyse song" shows. [spec] is the spectrogram: [cols] columns of [h] bytes (0..255), low pitch first. */
class AnalysisResult(
    val rate: Int,
    val channels: Int,
    val peakDb: Double,
    val clip: Int,
    val lufs: Double?,
    val dr: Double?,
    val bits: Int,          // bit depth the file claims (0 = unknown)
    val eff: Int?,          // bit depth the audio really uses (null = cannot tell)
    val cutoff: Double,     // Hz where the content stops
    val cols: Int,
    val h: Int,
    val spec: ByteArray,
)

/**
 * Reads a whole song once and measures it: spectrogram, bandwidth (is hi-res really hi-res?), real bit depth,
 * loudness, peak, clipping and an estimate of dynamic range. The same methods as the web version, but streaming,
 * so even a very long hi-res file needs very little memory.
 */
@OptIn(UnstableApi::class)
object SongAnalyzer {
    private const val N = 4096
    private const val H = N / 2
    private const val COLS = 280
    private const val MAX_SECONDS = 30 * 60

    private val hann = DoubleArray(N) { 0.5 - 0.5 * cos(2.0 * PI * it / (N - 1)) }
    private val cosT = DoubleArray(N / 2) { cos(-2.0 * PI * it / N) }
    private val sinT = DoubleArray(N / 2) { sin(-2.0 * PI * it / N) }

    private fun fft(re: DoubleArray, im: DoubleArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                val tr = re[i]; re[i] = re[j]; re[j] = tr
                val ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var len = 2
        while (len <= n) {
            val half = len / 2
            val step = n / len
            var i = 0
            while (i < n) {
                for (k in 0 until half) {
                    val wr = cosT[k * step]
                    val wi = sinT[k * step]
                    val a = i + k
                    val b = a + half
                    val tr = re[b] * wr - im[b] * wi
                    val ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                }
                i += len
            }
            len = len shl 1
        }
    }

    /** Finds a brick-wall cut-off (lossy or upsampled files). Otherwise the highest pitch that still has content. */
    private fun cutoff(av: DoubleArray, fs: Int): Double {
        val n = av.size
        val bw = fs / 2.0 / n
        fun smooth(w: Int): DoubleArray {
            val ps = DoubleArray(n + 1)
            for (i in 0 until n) ps[i + 1] = ps[i] + av[i]
            return DoubleArray(n) { i ->
                val lo = max(0, i - w)
                val hi = min(n - 1, i + w)
                (ps[hi + 1] - ps[lo]) / (hi - lo + 1)
            }
        }
        val g = max(2, (600.0 / bw).roundToInt())
        val sm = smooth(max(1, (150.0 / bw).roundToInt()))
        fun dd(i: Int) = sm[i - g] - sm[i + g]
        var bi = -1
        var bd = 0.0
        for (i in g until n - g) {
            val d = dd(i)
            if (i * bw > 8000 && d > bd) { bd = d; bi = i }
        }
        if (bd >= 25 && bi >= 0) {
            var lo = bi
            var hi = bi
            while (lo > g && dd(lo - 1) >= bd - 3) lo--
            while (hi < n - g - 1 && dd(hi + 1) >= bd - 3) hi++
            return (lo + hi) / 2.0 * bw
        }
        val s2 = smooth(max(1, (300.0 / bw).roundToInt()))
        val sorted = s2.sortedArray()
        val fl = sorted[(n * 0.05).toInt()]
        val med = sorted[n / 2]
        val thr = fl + min(10.0, (med - fl) * 0.5)
        for (i in n - 1 downTo 1) if (s2[i] > thr) return i * bw
        return 0.0
    }

    /** Why the last analysis failed, for the screen. */
    @Volatile var lastError = ""

    /** First with float samples (keeps all 24 bits). If that fails on this phone, again with the plain 16-bit decoder. */
    fun run(
        ctx: Context, uri: Uri, aiff: Boolean, fileBits: Int, hintMs: Long,
        cancelled: () -> Boolean, progress: (Float) -> Unit,
    ): AnalysisResult? {
        lastError = ""
        // FLAC is read with Athana's own decoder first: it works on every phone and keeps all the bits.
        if (!aiff) {
            val o = attemptOwnFlac(ctx, uri, fileBits, hintMs, cancelled, progress)
            if (o != null || cancelled()) return o
        }
        val own = lastError
        lastError = ""
        val a = attempt(ctx, uri, aiff, fileBits, hintMs, cancelled, progress, true)
        if (a != null || cancelled()) return a
        val first = lastError
        val b = attempt(ctx, uri, aiff, fileBits, hintMs, cancelled, progress, false)
        if (b == null) {
            val parts = listOf(own, first, if (lastError == first) "" else lastError).filter { it.isNotEmpty() }
            lastError = parts.joinToString(" | then: ")
        }
        return b
    }


    // ------------------------------------------------------------------ FLAC with Athana's own decoder
    private fun readFully(ins: java.io.InputStream, b: ByteArray, n: Int): Boolean {
        var o = 0
        while (o < n) {
            val r = ins.read(b, o, n - o)
            if (r < 0) return false
            o += r
        }
        return true
    }

    private fun skipFully(ins: java.io.InputStream, n: Long): Boolean {
        var left = n
        while (left > 0) {
            val s = ins.skip(left)
            if (s > 0) left -= s else {
                if (ins.read() < 0) return false
                left--
            }
        }
        return true
    }

    /** Reads the FLAC header blocks (and a leading ID3 tag) and leaves the stream at the first audio frame. Null when this is not a FLAC file. */
    private fun readStreamInfo(ins: java.io.InputStream): AthanaFlac.Info? {
        val head = ByteArray(4)
        if (!readFully(ins, head, 4)) return null
        if (head[0] == 'I'.code.toByte() && head[1] == 'D'.code.toByte() && head[2] == '3'.code.toByte()) {
            val rest = ByteArray(6)
            if (!readFully(ins, rest, 6)) return null
            val size = ((rest[2].toInt() and 0x7F) shl 21) or ((rest[3].toInt() and 0x7F) shl 14) or ((rest[4].toInt() and 0x7F) shl 7) or (rest[5].toInt() and 0x7F)
            if (!skipFully(ins, size.toLong())) return null
            if (!readFully(ins, head, 4)) return null
        }
        if (head[0] != 'f'.code.toByte() || head[1] != 'L'.code.toByte() || head[2] != 'a'.code.toByte() || head[3] != 'C'.code.toByte()) return null
        var info: AthanaFlac.Info? = null
        while (true) {
            val h = ByteArray(4)
            if (!readFully(ins, h, 4)) return null
            val last = (h[0].toInt() and 0x80) != 0
            val type = h[0].toInt() and 0x7F
            val len = ((h[1].toInt() and 255) shl 16) or ((h[2].toInt() and 255) shl 8) or (h[3].toInt() and 255)
            if (type == 0 && len >= 34) {
                val d = ByteArray(len)
                if (!readFully(ins, d, len)) return null
                info = AthanaFlac.parseStreamInfo(d.copyOf(34))
            } else if (!skipFully(ins, len.toLong())) return null
            if (last) break
        }
        return info
    }

    /**
     * FLAC read and decoded by Athana itself, frame by frame. It does not depend on the phone's own FLAC decoder (some
     * phones and emulators fail on it) and it keeps every bit, so the real bit depth can always be measured.
     * Returns null when the file is not FLAC or cannot be read; [lastError] then says why, when it knows.
     */
    private fun attemptOwnFlac(
        ctx: Context, uri: Uri, fileBitsIn: Int, hintMs: Long,
        cancelled: () -> Boolean, progress: (Float) -> Unit,
    ): AnalysisResult? {
        var ins: java.io.InputStream? = null
        try {
            val stream = ctx.contentResolver.openInputStream(uri) ?: return null
            ins = stream
            val flacInfo = readStreamInfo(stream) ?: return null
            val fileBits = if (fileBitsIn in 8..24) fileBitsIn else flacInfo.bitsPerSample
            var rate = flacInfo.sampleRate
            var ch = flacInfo.channels
            val totalSec = max(1.0, if (flacInfo.totalSamples > 0) flacInfo.totalSamples.toDouble() / rate else hintMs / 1000.0)
            val estFrames = (totalSec * rate).toLong()
            if (totalSec > MAX_SECONDS) { lastError = "The song is longer than 30 minutes"; return null }
            var enc = 2
            var meter = LoudnessMeter(rate, ch)
            var peak = 0.0
            var clip = 0
            var runs = IntArray(ch)
            var sumSq = 0.0
            var rmsN = 0
            val l3 = rate * 3
            val rms = ArrayList<Double>()
            val ring = DoubleArray(N)
            var g = 0L
            val ends = LongArray(COLS) { x ->
                val s = floor((estFrames - N).toDouble() * (x + 0.5) / COLS).toLong()
                s + N - 1
            }
            val canSpec = estFrames > N
            var nextCol = 0
            val spec = ByteArray(COLS * H)
            val avg = DoubleArray(H)
            var used = 0
            val re = DoubleArray(N)
            val im = DoubleArray(N)
            val bitsOn = fileBits in 8..24
            val scale = if (bitsOn) Math.pow(2.0, (fileBits - 1).toDouble()) else 1.0
            var orv = 0L
            var orCount = 0

            fun column(x: Int, gEnd: Long) {
                for (i in 0 until N) {
                    val idx = (((gEnd - N + 1 + i) % N) + N) % N
                    re[i] = ring[idx.toInt()] * hann[i]
                    im[i] = 0.0
                }
                fft(re, im)
                val norm = (N / 4.0) * (N / 4.0)
                for (k in 0 until H) {
                    val p = (re[k] * re[k] + im[k] * im[k]) / norm
                    val d = 10.0 * log10(p + 1e-18)
                    spec[x * H + k] = ((d + 130.0) / 105.0 * 255.0).roundToInt().coerceIn(0, 255).toByte()
                    avg[k] += p
                }
                used++
            }

            fun feed(x: FloatArray, frames: Int) {
                meter.add(x, frames)
                for (f in 0 until frames) {
                    val base = f * ch
                    for (c in 0 until ch) {
                        val v = x[base + c].toDouble()
                        val a = abs(v)
                        if (a > peak) peak = a
                        if (a >= 0.9999) { if (++runs[c] == 3) clip++ } else runs[c] = 0
                        sumSq += v * v
                    }
                    if (bitsOn && enc == 4 && g % 7L == 0L && orCount < 600000) {
                        val iv = Math.round(abs(x[base].toDouble()) * scale)
                        if (iv != 0L) { orv = orv or iv; orCount++ }
                    }
                    ring[(g % N).toInt()] = x[base].toDouble()
                    if (++rmsN >= l3) { rms.add(sumSq / (ch.toDouble() * l3)); sumSq = 0.0; rmsN = 0 }
                    if (canSpec) {
                        while (nextCol < COLS && g == ends[nextCol]) { column(nextCol, g); nextCol++ }
                    }
                    g++
                }
            }

            enc = 4   // Athana's decoder gives every bit
            val flac = AthanaFlac(flacInfo.bitsPerSample, flacInfo.sampleRate)
            val outBytes = flacInfo.outBytes()
            val unit = 1.0 / (1L shl (8 * outBytes - 1)).toDouble()
            val buf = ByteArray(2 * 1024 * 1024)
            val scratch = java.nio.ByteBuffer.allocate(65535 * ch * outBytes)
            var len = 0
            var pos = 0
            var eof = false
            var tmp = FloatArray(0)
            var lastP = 0L
            var bad = 0
            while (!cancelled()) {
                if (!eof && len - pos < 1000000) {
                    System.arraycopy(buf, pos, buf, 0, len - pos)
                    len -= pos
                    pos = 0
                    while (len < buf.size) {
                        val r = stream.read(buf, len, buf.size - len)
                        if (r < 0) { eof = true; break }
                        len += r
                    }
                }
                if (pos >= len) break
                scratch.clear()
                var bytes = -1
                try {
                    bytes = flac.decodeFrame(buf, pos, len - pos, scratch, outBytes)
                    if (flac.lastChannels != ch || flac.lastConsumed <= 0) bytes = -1
                } catch (_: Throwable) { bytes = -1 }
                if (bytes < 0) {
                    // A damaged frame, or data after the music (a tag): look for the next frame start.
                    if (++bad > 200) break
                    pos++
                    while (pos + 1 < len && !((buf[pos].toInt() and 0xFF) == 0xFF && (buf[pos + 1].toInt() and 0xFC) == 0xF8)) pos++
                    continue
                }
                bad = 0
                pos += flac.lastConsumed
                scratch.flip()
                val frames = bytes / (ch * outBytes)
                if (tmp.size < frames * ch) tmp = FloatArray(frames * ch)
                var o = 0
                for (k in 0 until frames * ch) {
                    val v: Int = when (outBytes) {
                        2 -> ((scratch.get(o).toInt() and 0xFF) or (scratch.get(o + 1).toInt() shl 8))
                        3 -> ((scratch.get(o).toInt() and 0xFF) or ((scratch.get(o + 1).toInt() and 0xFF) shl 8) or (scratch.get(o + 2).toInt() shl 16))
                        else -> ((scratch.get(o).toInt() and 0xFF) or ((scratch.get(o + 1).toInt() and 0xFF) shl 8) or ((scratch.get(o + 2).toInt() and 0xFF) shl 16) or (scratch.get(o + 3).toInt() shl 24))
                    }
                    o += outBytes
                    tmp[k] = (v * unit).toFloat()
                }
                feed(tmp, frames)
                val now = System.currentTimeMillis()
                if (now - lastP > 250) { lastP = now; progress(min(1f, (g.toDouble() / (totalSec * rate)).toFloat())) }
            }
            if (cancelled()) return null
            if (g < rate) { lastError = "The song is shorter than one second, or the decoder gave no audio (decoded $g samples)"; return null }

            val peakDb = if (peak > 0.0) 20.0 * log10(peak) else -120.0
            var dr: Double? = null
            if (rms.size >= 3) {
                rms.sortDescending()
                val top = rms.take(max(1, (rms.size * 0.2).roundToInt()))
                val m = top.average()
                if (m > 0.0) dr = peakDb - 10.0 * log10(m)
            }
            // Real bit depth: how many of the lowest bits are always zero. Only known when the decoder gave us the full precision.
            var eff: Int? = null
            if (bitsOn && enc == 4 && orv != 0L) eff = fileBits - java.lang.Long.numberOfTrailingZeros(orv).coerceAtMost(fileBits - 1)
            val cols = used
            val av = DoubleArray(H) { 10.0 * log10(avg[it] / max(1, used) + 1e-18) }
            val cut = if (used > 0) cutoff(av, rate) else 0.0
            return AnalysisResult(rate, ch, peakDb, clip, meter.result()?.lufs, dr, if (bitsOn) fileBits else 0, eff, cut, cols, H, spec.copyOf(cols * H))
        } catch (e: Throwable) {
            android.util.Log.e("Athana", "own FLAC analysis failed", e)
            val at = e.stackTrace.take(3).joinToString(" < ") { it.methodName + ":" + it.lineNumber }
            lastError = (e.javaClass.simpleName + ": " + (e.message ?: "") + " @ " + at + " [own FLAC]").take(260)
            return null
        } finally {
            try { ins?.close() } catch (_: Exception) { }
        }
    }

    private fun attempt(
        ctx: Context, uri: Uri, aiff: Boolean, fileBits: Int, hintMs: Long,
        cancelled: () -> Boolean, progress: (Float) -> Unit, wantFloat: Boolean,
    ): AnalysisResult? {
        val ex = MediaExtractor()
        var src: AiffMediaSource? = null
        var codec: MediaCodec? = null
        try {
            if (aiff) { src = AiffMediaSource(ctx, uri); ex.setDataSource(src) } else ex.setDataSource(ctx, uri, null)
            var track = -1
            var fmt: MediaFormat? = null
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                if ((f.getString(MediaFormat.KEY_MIME) ?: "").startsWith("audio/")) { track = i; fmt = f; break }
            }
            if (track < 0 || fmt == null) { lastError = "No audio track found"; return null }
            ex.selectTrack(track)
            // Ask for 32-bit float output, so 24-bit music keeps every bit. Decoders that cannot do it give 16-bit.
            if (wantFloat) try { fmt.setInteger(MediaFormat.KEY_PCM_ENCODING, 4) } catch (_: Exception) { }
            codec = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(fmt, null, null, 0)
            codec.start()

            var rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var ch = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val durUs = if (fmt.containsKey(MediaFormat.KEY_DURATION)) fmt.getLong(MediaFormat.KEY_DURATION) else hintMs * 1000L
            val totalSec = max(1.0, durUs / 1e6)
            val estFrames = (totalSec * rate).toLong()
            if (totalSec > MAX_SECONDS) { lastError = "The song is longer than 30 minutes"; return null }

            var enc = 2
            var meter = LoudnessMeter(rate, ch)
            var peak = 0.0
            var clip = 0
            var runs = IntArray(ch)
            var sumSq = 0.0
            var rmsN = 0
            val l3 = rate * 3
            val rms = ArrayList<Double>()
            val ring = DoubleArray(N)
            var g = 0L
            val ends = LongArray(COLS) { x ->
                val s = floor((estFrames - N).toDouble() * (x + 0.5) / COLS).toLong()
                s + N - 1
            }
            val canSpec = estFrames > N
            var nextCol = 0
            val spec = ByteArray(COLS * H)
            val avg = DoubleArray(H)
            var used = 0
            val re = DoubleArray(N)
            val im = DoubleArray(N)
            val bitsOn = fileBits in 8..24
            val scale = if (bitsOn) Math.pow(2.0, (fileBits - 1).toDouble()) else 1.0
            var orv = 0L
            var orCount = 0

            fun column(x: Int, gEnd: Long) {
                for (i in 0 until N) {
                    val idx = (((gEnd - N + 1 + i) % N) + N) % N
                    re[i] = ring[idx.toInt()] * hann[i]
                    im[i] = 0.0
                }
                fft(re, im)
                val norm = (N / 4.0) * (N / 4.0)
                for (k in 0 until H) {
                    val p = (re[k] * re[k] + im[k] * im[k]) / norm
                    val d = 10.0 * log10(p + 1e-18)
                    spec[x * H + k] = ((d + 130.0) / 105.0 * 255.0).roundToInt().coerceIn(0, 255).toByte()
                    avg[k] += p
                }
                used++
            }

            fun feed(x: FloatArray, frames: Int) {
                meter.add(x, frames)
                for (f in 0 until frames) {
                    val base = f * ch
                    for (c in 0 until ch) {
                        val v = x[base + c].toDouble()
                        val a = abs(v)
                        if (a > peak) peak = a
                        if (a >= 0.9999) { if (++runs[c] == 3) clip++ } else runs[c] = 0
                        sumSq += v * v
                    }
                    if (bitsOn && enc == 4 && g % 7L == 0L && orCount < 600000) {
                        val iv = Math.round(abs(x[base].toDouble()) * scale)
                        if (iv != 0L) { orv = orv or iv; orCount++ }
                    }
                    ring[(g % N).toInt()] = x[base].toDouble()
                    if (++rmsN >= l3) { rms.add(sumSq / (ch.toDouble() * l3)); sumSq = 0.0; rmsN = 0 }
                    if (canSpec) {
                        while (nextCol < COLS && g == ends[nextCol]) { column(nextCol, g); nextCol++ }
                    }
                    g++
                }
            }

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var tmp = FloatArray(0)
            var idle = 0
            var lastP = 0L
            while (!outputDone && !cancelled()) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(5000)
                    if (i >= 0) {
                        val buf = codec.getInputBuffer(i)!!
                        val n = ex.readSampleData(buf, 0)
                        if (n < 0) {
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
                        if (g == 0L && (nr != rate || nc != ch)) {
                            rate = nr; ch = nc
                            meter = LoudnessMeter(rate, ch)
                            runs = IntArray(ch)
                        }
                    }
                    o >= 0 -> {
                        idle = 0
                        val out = codec.getOutputBuffer(o)
                        if (out != null && info.size > 0) {
                            out.position(info.offset)
                            out.limit(info.offset + info.size)
                            out.order(ByteOrder.nativeOrder())
                            val frames: Int
                            if (enc == 4) {
                                val fb = out.asFloatBuffer()
                                frames = fb.remaining() / ch
                                if (tmp.size < frames * ch) tmp = FloatArray(frames * ch)
                                fb.get(tmp, 0, frames * ch)
                            } else if (enc == 21) { // 24-bit packed
                                frames = out.remaining() / 3 / ch
                                if (tmp.size < frames * ch) tmp = FloatArray(frames * ch)
                                for (k in 0 until frames * ch) {
                                    val lo = out.get().toInt() and 0xFF
                                    val mid = out.get().toInt() and 0xFF
                                    val hi = out.get().toInt()
                                    tmp[k] = (((hi shl 16) or (mid shl 8) or lo) / 8388608.0).toFloat()
                                }
                            } else if (enc == 22) { // 32-bit
                                val ib = out.asIntBuffer()
                                frames = ib.remaining() / ch
                                if (tmp.size < frames * ch) tmp = FloatArray(frames * ch)
                                for (k in 0 until frames * ch) tmp[k] = (ib.get() / 2147483648.0).toFloat()
                            } else {
                                val sb = out.asShortBuffer()
                                frames = sb.remaining() / ch
                                if (tmp.size < frames * ch) tmp = FloatArray(frames * ch)
                                for (k in 0 until frames * ch) tmp[k] = sb.get() / 32768f
                            }
                            feed(tmp, frames)
                            val now = System.currentTimeMillis()
                            if (now - lastP > 250) { lastP = now; progress(min(1f, (g.toDouble() / (totalSec * rate)).toFloat())) }
                        }
                        codec.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                    else -> { if (inputDone && ++idle > 400) outputDone = true }
                }
            }
            if (cancelled()) return null
            if (g < rate) { lastError = "The song is shorter than one second, or the decoder gave no audio (decoded $g samples)"; return null }

            val peakDb = if (peak > 0.0) 20.0 * log10(peak) else -120.0
            var dr: Double? = null
            if (rms.size >= 3) {
                rms.sortDescending()
                val top = rms.take(max(1, (rms.size * 0.2).roundToInt()))
                val m = top.average()
                if (m > 0.0) dr = peakDb - 10.0 * log10(m)
            }
            // Real bit depth: how many of the lowest bits are always zero. Only known when the decoder gave us the full precision.
            var eff: Int? = null
            if (bitsOn && enc == 4 && orv != 0L) eff = fileBits - java.lang.Long.numberOfTrailingZeros(orv).coerceAtMost(fileBits - 1)
            val cols = used
            val av = DoubleArray(H) { 10.0 * log10(avg[it] / max(1, used) + 1e-18) }
            val cut = if (used > 0) cutoff(av, rate) else 0.0
            return AnalysisResult(rate, ch, peakDb, clip, meter.result()?.lufs, dr, if (bitsOn) fileBits else 0, eff, cut, cols, H, spec.copyOf(cols * H))
        } catch (e: Throwable) {
            android.util.Log.e("Athana", "analysis failed (float=$wantFloat)", e)
            // Name the place where it went wrong, so a message with no text of its own can still be traced.
            val at = e.stackTrace.take(3).joinToString(" < ") { it.methodName + ":" + it.lineNumber }
            lastError = (e.javaClass.simpleName + ": " + (e.message ?: "") + " @ " + at + (if (wantFloat) " [float]" else " [16-bit]")).take(260)
            return null
        } finally {
            try { codec?.stop() } catch (_: Exception) { }
            try { codec?.release() } catch (_: Exception) { }
            try { ex.release() } catch (_: Exception) { }
            try { src?.close() } catch (_: Exception) { }
        }
    }
}

package com.athana.lossless

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import java.io.FileInputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

/**
 * Lets ExoPlayer play AIFF / AIFF-C straight from storage.
 *
 * Android has no AIFF reader, so this presents the file to the player as a normal WAV stream: a 44-byte WAV header
 * followed by the same audio samples with their bytes swapped (AIFF is big-endian, WAV is little-endian).
 * Nothing is copied or decoded up front, so a song starts at once and seeking is instant. The samples are not
 * changed in any other way (bit-perfect).
 *
 * Supported: AIFF and AIFF-C with NONE / twos / sowt / in24 / in32 / raw / fl32 (8, 16, 24 and 32 bit, any channel count).
 */
@OptIn(UnstableApi::class)
class AiffWavDataSource(private val context: Context) : BaseDataSource(/* isNetwork = */ false) {

    private var uri: Uri? = null
    private var pfd: ParcelFileDescriptor? = null
    private var channel: FileChannel? = null
    private var opened = false

    private val head = ByteArray(HEAD)
    private var inBytes = 2
    private var swap = false      // big-endian samples that must be reversed
    private var flip = false      // signed 8-bit samples that must become unsigned (WAV rule)
    private var ssndStart = 0L    // where the audio starts in the file
    private var dataSize = 0L     // audio bytes
    private var total = 0L        // header + audio
    private var pos = 0L
    private var remaining = 0L

    private var chunk = ByteArray(0)
    private var chunkStart = -1L
    private var chunkLen = 0
    private var chunkMax = 0

    override fun open(dataSpec: DataSpec): Long {
        uri = dataSpec.uri
        transferInitializing(dataSpec)
        try {
            val p = context.contentResolver.openFileDescriptor(dataSpec.uri, "r") ?: throw IOException("Cannot open file")
            pfd = p
            channel = FileInputStream(p.fileDescriptor).channel
            parse()
        } catch (e: Exception) {
            close()
            throw if (e is IOException) e else IOException(e)
        }
        pos = dataSpec.position
        if (pos > total) { close(); throw IOException("Position out of range") }
        remaining = if (dataSpec.length != C.LENGTH_UNSET.toLong()) minOf(dataSpec.length, total - pos) else total - pos
        opened = true
        transferStarted(dataSpec)
        return remaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        var want = minOf(length.toLong(), remaining).toInt()
        var done = 0
        while (want > 0) {
            val n: Int
            if (pos < HEAD) {
                n = minOf(want.toLong(), HEAD - pos).toInt()
                System.arraycopy(head, pos.toInt(), buffer, offset + done, n)
            } else {
                val dp = pos - HEAD
                if (dp < chunkStart || dp >= chunkStart + chunkLen) fill(dp)
                n = minOf(want.toLong(), chunkStart + chunkLen - dp).toInt()
                System.arraycopy(chunk, (dp - chunkStart).toInt(), buffer, offset + done, n)
            }
            pos += n; remaining -= n; done += n; want -= n
        }
        bytesTransferred(done)
        return done
    }

    override fun getUri(): Uri? = uri

    override fun close() {
        try { channel?.close() } catch (_: Exception) { }
        try { pfd?.close() } catch (_: Exception) { }
        channel = null; pfd = null; uri = null
        if (opened) { opened = false; transferEnded() }
    }

    // ---- reading the AIFF header ----
    private fun readAt(position: Long, dst: ByteArray, len: Int): Int {
        val ch = channel ?: throw IOException("Closed")
        val bb = ByteBuffer.wrap(dst, 0, len)
        ch.position(position)
        var got = 0
        while (got < len) {
            val r = ch.read(bb)
            if (r < 0) break
            got += r
        }
        return got
    }

    private fun u16(b: ByteArray, o: Int) = ((b[o].toInt() and 255) shl 8) or (b[o + 1].toInt() and 255)
    private fun u32(b: ByteArray, o: Int) =
        ((b[o].toLong() and 255) shl 24) or ((b[o + 1].toLong() and 255) shl 16) or ((b[o + 2].toLong() and 255) shl 8) or (b[o + 3].toLong() and 255)

    private fun parse() {
        val ch = channel ?: throw IOException("Closed")
        val fileLen = ch.size()
        val tmp = ByteArray(64)

        var base = 0L                                   // skip an ID3 tag if the file starts with one
        if (readAt(0, tmp, 10) == 10 && tmp[0] == 'I'.code.toByte() && tmp[1] == 'D'.code.toByte() && tmp[2] == '3'.code.toByte()) {
            base = (((tmp[6].toInt() and 0x7f) shl 21) or ((tmp[7].toInt() and 0x7f) shl 14) or
                    ((tmp[8].toInt() and 0x7f) shl 7) or (tmp[9].toInt() and 0x7f)).toLong() + 10
        }
        if (readAt(base, tmp, 12) < 12 || String(tmp, 0, 4, Charsets.ISO_8859_1) != "FORM") throw IOException("Not an AIFF file")
        val form = String(tmp, 8, 4, Charsets.ISO_8859_1)
        if (form != "AIFF" && form != "AIFC") throw IOException("Not an AIFF file")

        var channels = 0; var bits = 0; var rate = 0L; var comp = "NONE"
        var ssnd = 0L; var ssndSize = 0L
        var off = base + 12
        while (off + 8 <= fileLen) {
            if (readAt(off, tmp, 8) < 8) break
            val id = String(tmp, 0, 4, Charsets.ISO_8859_1)
            val size = u32(tmp, 4)
            if (id == "COMM") {
                val n = minOf(size, 40L).toInt()
                if (readAt(off + 8, tmp, n) < n || n < 18) throw IOException("Bad COMM chunk")
                channels = ((tmp[0].toInt() shl 8) or (tmp[1].toInt() and 255)).toShort().toInt()
                bits = ((tmp[6].toInt() shl 8) or (tmp[7].toInt() and 255)).toShort().toInt()
                val exp = u16(tmp, 8) and 0x7fff
                val mant = u32(tmp, 10)
                rate = Math.round(mant.toDouble() * Math.pow(2.0, (exp - 16383 - 31).toDouble()))
                if (form == "AIFC" && n >= 22) comp = String(tmp, 18, 4, Charsets.ISO_8859_1)
            } else if (id == "SSND") {
                if (readAt(off + 8, tmp, 8) < 8) throw IOException("Bad SSND chunk")
                val od = u32(tmp, 0)
                ssnd = off + 16 + od
                ssndSize = size - 8 - od
            }
            off += 8 + size + (size and 1L)
        }
        if (channels <= 0 || ssnd == 0L || rate <= 0) throw IOException("Invalid AIFF structure")

        var le = false; var float = false; var raw8 = false
        when (comp.lowercase()) {
            "none", "twos", "in24", "in32" -> { }
            "sowt" -> le = true
            "raw " -> raw8 = true
            "fl32" -> float = true
            else -> throw IOException("Unsupported AIFF-C compression: $comp")
        }
        inBytes = (bits + 7) / 8
        if (inBytes !in 1..4 || (float && inBytes != 4)) throw IOException("Unsupported sample size: $bits")

        val frame = channels * inBytes
        var size = minOf(ssndSize, fileLen - ssnd)
        size -= size % frame
        if (size <= 0) throw IOException("No audio data")

        swap = !le && inBytes > 1
        flip = inBytes == 1 && !raw8
        ssndStart = ssnd
        dataSize = size
        total = HEAD + size

        ByteBuffer.wrap(head).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray()); putInt((36 + size + (size and 1L)).toInt()); put("WAVE".toByteArray())
            put("fmt ".toByteArray()); putInt(16); putShort((if (float) 3 else 1).toShort()); putShort(channels.toShort())
            putInt(rate.toInt()); putInt((rate * frame).toInt()); putShort(frame.toShort()); putShort((inBytes * 8).toShort())
            put("data".toByteArray()); putInt(size.toInt())
        }
        chunkMax = (1 shl 16) / inBytes * inBytes
        chunk = ByteArray(chunkMax)
        chunkStart = -1; chunkLen = 0
    }

    /** Reads the next block of audio around dataPosition and converts it to little-endian. */
    private fun fill(dp: Long) {
        val start = dp - dp % inBytes
        val len = minOf(chunkMax.toLong(), dataSize - start).toInt()
        if (len <= 0) throw IOException("Read past the end")
        if (readAt(ssndStart + start, chunk, len) < len) throw IOException("Unexpected end of file")
        if (swap) {
            var i = 0
            while (i + inBytes <= len) {
                var a = i; var b = i + inBytes - 1
                while (a < b) { val t = chunk[a]; chunk[a] = chunk[b]; chunk[b] = t; a++; b-- }
                i += inBytes
            }
        } else if (flip) {
            for (i in 0 until len) chunk[i] = (chunk[i].toInt() xor 0x80).toByte()
        }
        chunkStart = start
        chunkLen = len
    }

    private companion object {
        const val HEAD = 44
    }
}

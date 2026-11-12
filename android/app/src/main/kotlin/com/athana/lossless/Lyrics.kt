package com.athana.lossless

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.charset.Charset

/**
 * Reads lyrics saved inside a song file: MP3 / AIFF / WAV (ID3 USLT, SYLT, TXXX), FLAC (LYRICS comment) and M4A (the (c)lyr atom).
 * Android cannot do this by itself. Synced lyrics come back as LRC text, so the app treats every source the same.
 */
object LyricsReader {
    private val latin1: Charset = Charsets.ISO_8859_1
    private val stamp = Regex("\\[\\d{1,3}:\\d{2}")

    fun read(ctx: Context, uri: Uri): String? {
        return try {
            val pfd = ctx.contentResolver.openFileDescriptor(uri, "r") ?: return null
            ParcelFileDescriptor.AutoCloseInputStream(pfd).use { ins ->
                val ch = ins.channel
                val size = ch.size()
                val head = readAt(ch, 0L, 12)
                if (head.size < 8) return@use null
                val tag = String(head, 0, 4, latin1)
                val r = when {
                    head[0] == 'I'.code.toByte() && head[1] == 'D'.code.toByte() && head[2] == '3'.code.toByte() -> id3At(ch, 0L, size)
                    tag == "fLaC" -> flac(ch, size)
                    tag == "FORM" || tag == "RIFF" -> container(ch, size, tag == "RIFF")
                    String(head, 4, 4, latin1) == "ftyp" -> mp4(ch, size)
                    else -> null
                }
                r?.trim()?.takeIf { it.isNotEmpty() }
            }
        } catch (_: Exception) {
            null
        }
    }

    // ------------------------------------------------------------------ AIFF / WAV: an "ID3 " chunk
    private fun container(ch: FileChannel, total: Long, le: Boolean): String? {
        var off = 12L
        while (off + 8 <= total) {
            val h = readAt(ch, off, 8)
            if (h.size < 8) break
            val id = String(h, 0, 4, latin1)
            val size = u32(h, 4, le)
            val body = off + 8
            if (id.equals("id3 ", ignoreCase = true)) return id3At(ch, body, minOf(total, body + size))
            off = body + size + (size and 1L)
        }
        return null
    }

    // ------------------------------------------------------------------ ID3v2
    private fun id3At(ch: FileChannel, start: Long, limit: Long): String? {
        val h = readAt(ch, start, 10)
        if (h.size < 10 || String(h, 0, 3, latin1) != "ID3") return null
        val ver = h[3].toInt() and 0xFF
        val flags = h[5].toInt() and 0xFF
        val tagSize = syncsafe(h, 6)
        val n = minOf(tagSize.toLong(), 24_000_000L, limit - start - 10).toInt()
        if (n <= 0) return null
        var b = readAt(ch, start + 10, n)
        if (ver == 3 && (flags and 0x80) != 0) b = deunsync(b)
        var p = 0
        if ((flags and 0x40) != 0 && b.size >= 4) {          // extended header
            p = if (ver == 4) syncsafe(b, 0) else (u32(b, 0, false).toInt() + 4)
            if (p < 0 || p > b.size) p = 0
        }
        val idLen = if (ver == 2) 3 else 4
        val hdr = if (ver == 2) 6 else 10
        var uslt: String? = null
        var sylt: String? = null
        var txxx: String? = null
        while (p + hdr <= b.size) {
            if (b[p].toInt() == 0) break
            val id = String(b, p, idLen, latin1)
            var sz = when (ver) {
                2 -> ((b[p + 3].toInt() and 0xFF) shl 16) or ((b[p + 4].toInt() and 0xFF) shl 8) or (b[p + 5].toInt() and 0xFF)
                4 -> syncsafe(b, p + 4)
                else -> u32(b, p + 4, false).toInt()
            }
            val fl = if (ver == 2) 0 else (((b[p + 8].toInt() and 0xFF) shl 8) or (b[p + 9].toInt() and 0xFF))
            val ds = p + hdr
            if (sz < 0 || ds + sz > b.size) sz = maxOf(0, b.size - ds)
            var fd = b.copyOfRange(ds, ds + sz)
            if (ver == 4) {
                if ((fl and 0x0001) != 0 && fd.size > 4) fd = fd.copyOfRange(4, fd.size)   // data length indicator
                if ((fl and 0x0002) != 0) fd = deunsync(fd)
            }
            try {
                when (id) {
                    "USLT", "ULT" -> if (uslt == null) uslt = textFrame(fd)
                    "SYLT", "SLT" -> if (sylt == null) sylt = syncFrame(fd)
                    "TXXX", "TXX" -> if (txxx == null) txxx = userText(fd)
                }
            } catch (_: Exception) { }
            p = ds + sz
        }
        val all = listOf(uslt, sylt, txxx).filter { !it.isNullOrBlank() }
        return all.firstOrNull { stamp.containsMatchIn(it!!) } ?: all.firstOrNull()
    }

    /** USLT: encoding, language, a short description, then the text. */
    private fun textFrame(d: ByteArray): String? {
        if (d.size < 5) return null
        val enc = d[0].toInt() and 0xFF
        val t = termAt(d, 4, enc)
        if (t < 0) return null
        return decode(d, t + (if (enc == 1 || enc == 2) 2 else 1), d.size, enc).trimEnd('\u0000')
    }

    /** TXXX with a description such as LYRICS. */
    private fun userText(d: ByteArray): String? {
        if (d.size < 3) return null
        val enc = d[0].toInt() and 0xFF
        val t = termAt(d, 1, enc)
        if (t < 0) return null
        val key = decode(d, 1, t, enc)
        if (!key.contains("LYRIC", ignoreCase = true)) return null
        return decode(d, t + (if (enc == 1 || enc == 2) 2 else 1), d.size, enc).trimEnd('\u0000')
    }

    /** SYLT: lines with time stamps in milliseconds, turned into LRC. */
    private fun syncFrame(d: ByteArray): String? {
        if (d.size < 8) return null
        val enc = d[0].toInt() and 0xFF
        val fmt = d[4].toInt() and 0xFF
        if (fmt != 2) return null                                  // time in MPEG frames cannot be turned into seconds
        val step = if (enc == 1 || enc == 2) 2 else 1
        val t = termAt(d, 6, enc)
        if (t < 0) return null
        var p = t + step
        val sb = StringBuilder()
        while (p < d.size) {
            val e = termAt(d, p, enc)
            if (e < 0 || e + step + 4 > d.size) break
            val text = decode(d, p, e, enc).replace("\n", " ").trim()
            val ms = u32(d, e + step, false)
            p = e + step + 4
            if (text.isEmpty()) continue
            val cs = (ms / 10) % 100
            val sec = (ms / 1000) % 60
            val min = ms / 60000
            sb.append(String.format("[%02d:%02d.%02d]%s\n", min, sec, cs, text))
        }
        return sb.toString().takeIf { it.isNotBlank() }
    }

    private fun termAt(d: ByteArray, from: Int, enc: Int): Int {
        if (enc == 1 || enc == 2) {
            var i = from
            while (i + 1 < d.size) {
                if (d[i].toInt() == 0 && d[i + 1].toInt() == 0) return i
                i += 2
            }
            return -1
        }
        for (i in from until d.size) if (d[i].toInt() == 0) return i
        return -1
    }

    private fun decode(d: ByteArray, from: Int, to: Int, enc: Int): String {
        if (to <= from) return ""
        val cs: Charset = when (enc) {
            1 -> Charsets.UTF_16
            2 -> Charsets.UTF_16BE
            3 -> Charsets.UTF_8
            else -> latin1
        }
        return String(d, from, to - from, cs)
    }

    private fun deunsync(b: ByteArray): ByteArray {
        val o = java.io.ByteArrayOutputStream(b.size)
        var i = 0
        while (i < b.size) {
            o.write(b[i].toInt())
            if (b[i] == 0xFF.toByte() && i + 1 < b.size && b[i + 1].toInt() == 0) i++
            i++
        }
        return o.toByteArray()
    }

    // ------------------------------------------------------------------ FLAC: Vorbis comments
    private fun flac(ch: FileChannel, total: Long): String? {
        var p = 4L
        while (p + 4 <= total) {
            val h = readAt(ch, p, 4)
            if (h.size < 4) break
            val last = (h[0].toInt() and 0x80) != 0
            val type = h[0].toInt() and 0x7F
            val len = ((h[1].toInt() and 0xFF) shl 16) or ((h[2].toInt() and 0xFF) shl 8) or (h[3].toInt() and 0xFF)
            if (type == 4 && len in 8..8_000_000) {
                val b = readAt(ch, p + 4, len)
                var o = 0
                if (b.size < 8) return null
                val vendor = u32(b, o, true).toInt(); o += 4 + vendor
                if (o + 4 > b.size) return null
                val n = u32(b, o, true).toInt(); o += 4
                val found = ArrayList<String>()
                for (i in 0 until n) {
                    if (o + 4 > b.size) break
                    val l = u32(b, o, true).toInt(); o += 4
                    if (l < 0 || o + l > b.size) break
                    val s = String(b, o, l, Charsets.UTF_8); o += l
                    val k = s.indexOf('=')
                    if (k > 0) {
                        val key = s.substring(0, k).uppercase()
                        if (key == "LYRICS" || key == "UNSYNCEDLYRICS" || key == "SYNCEDLYRICS" || key == "LYRICS_SYNCED") {
                            val v = s.substring(k + 1)
                            if (v.isNotBlank()) found.add(v)
                        }
                    }
                }
                return found.firstOrNull { stamp.containsMatchIn(it) } ?: found.firstOrNull()
            }
            p += 4L + len
            if (last) break
        }
        return null
    }

    // ------------------------------------------------------------------ M4A: moov / udta / meta / ilst / (c)lyr / data
    private fun mp4(ch: FileChannel, total: Long): String? {
        var r = atom(ch, 0L, total, "moov") ?: return null
        r = atom(ch, r.first, r.second, "udta") ?: return null
        r = atom(ch, r.first, r.second, "meta") ?: return null
        r = atom(ch, r.first + 4, r.second, "ilst") ?: return null
        r = atom(ch, r.first, r.second, "©lyr") ?: return null
        r = atom(ch, r.first, r.second, "data") ?: return null
        val n = (r.second - r.first - 8).toInt()
        if (n <= 0 || n > 8_000_000) return null
        return String(readAt(ch, r.first + 8, n), Charsets.UTF_8)
    }

    /** Finds a child atom between [start] and [end]; returns where its content begins and ends. */
    private fun atom(ch: FileChannel, start: Long, end: Long, want: String): Pair<Long, Long>? {
        var off = start
        while (off + 8 <= end) {
            val h = readAt(ch, off, 16)
            if (h.size < 8) return null
            var size = u32(h, 0, false)
            val type = String(h, 4, 4, latin1)
            var hdr = 8L
            if (size == 1L && h.size >= 16) {
                size = (u32(h, 8, false) shl 32) or u32(h, 12, false)
                hdr = 16L
            } else if (size == 0L) {
                size = end - off
            }
            if (size < hdr) return null
            if (type == want) return Pair(off + hdr, minOf(end, off + size))
            off += size
        }
        return null
    }

    // ------------------------------------------------------------------ helpers
    private fun readAt(ch: FileChannel, pos: Long, n: Int): ByteArray {
        if (n <= 0) return ByteArray(0)
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
        ((b[o].toInt() and 0x7F) shl 21) or ((b[o + 1].toInt() and 0x7F) shl 14) or ((b[o + 2].toInt() and 0x7F) shl 7) or (b[o + 3].toInt() and 0x7F)
}

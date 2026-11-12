package com.athana.lossless;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Athana's own FLAC decoder. It has no Android or library dependencies: it reads one FLAC frame
 * (the bytes between two frame sync codes) and writes the samples as little-endian PCM.
 *
 * Supported: every FLAC subframe type (constant, verbatim, fixed, LPC), all stereo modes, wasted bits,
 * both Rice codings, 4 to 32 bits per sample and 1 to 8 channels. Nothing is dithered or changed:
 * a sample with fewer bits than its output container is shifted left, which keeps it exact.
 */
public final class AthanaFlac {

    /** The facts from the STREAMINFO block. */
    public static final class Info {
        public int minBlock, maxBlock, sampleRate, channels, bitsPerSample;
        public long totalSamples;
        /** Bytes per sample in the output: 2, 3 or 4. */
        public int outBytes() { return bitsPerSample <= 16 ? 2 : (bitsPerSample <= 24 ? 3 : 4); }
    }

    /**
     * Reads STREAMINFO from the start-up data ExoPlayer gives (it may start with the "fLaC" marker and the 4 byte
     * block header, or be just the 34 byte block). Returns null if it does not look like STREAMINFO.
     */
    public static Info parseStreamInfo(byte[] d) {
        if (d == null) return null;
        int o = 0;
        if (d.length >= 4 && d[0] == 'f' && d[1] == 'L' && d[2] == 'a' && d[3] == 'C') o = 4;
        // a metadata block header: last flag + type (0 = STREAMINFO), then a 3 byte length of 34
        if (d.length - o >= 38 && (d[o] & 0x7F) == 0 && ((d[o + 1] & 255) << 16 | (d[o + 2] & 255) << 8 | (d[o + 3] & 255)) == 34) o += 4;
        if (d.length - o < 34) return null;
        Info in = new Info();
        in.minBlock = (d[o] & 255) << 8 | (d[o + 1] & 255);
        in.maxBlock = (d[o + 2] & 255) << 8 | (d[o + 3] & 255);
        long x = 0;
        for (int i = 0; i < 8; i++) x = (x << 8) | (d[o + 10 + i] & 255);
        in.sampleRate = (int) (x >>> 44);
        in.channels = (int) ((x >>> 41) & 7) + 1;
        in.bitsPerSample = (int) ((x >>> 36) & 31) + 1;
        in.totalSamples = x & 0xFFFFFFFFFL;
        if (in.sampleRate <= 0 || in.bitsPerSample < 4) return null;
        return in;
    }

    // ------------------------------------------------------------------------------------------------ the decoder
    private final int streamBps;      // from STREAMINFO, used when a frame says "as in STREAMINFO"
    private final int streamRate;
    private int[][] ch = new int[8][];
    private int[] resid = new int[0];
    // read state
    private byte[] buf;
    private int end;
    private int bytePos;
    private long cache;
    private int cacheBits;

    /** What the last decoded frame contained. */
    public int lastBlockSize, lastChannels, lastSampleRate, lastBps, lastConsumed;

    public AthanaFlac(int streamBitsPerSample, int streamSampleRate) {
        this.streamBps = streamBitsPerSample;
        this.streamRate = streamSampleRate;
    }

    /**
     * Decodes one frame found at the start of buf[off..off+len). The PCM is appended to [out], which must have room
     * for blockSize * channels * outBytes (use [maxOutBytes]). Returns the number of PCM bytes written.
     * After the call, [lastConsumed] is the size of the frame in bytes.
     */
    public int decodeFrame(byte[] data, int off, int len, ByteBuffer out, int outBytes) throws IOException {
        buf = data;
        bytePos = off;
        end = off + len;
        cache = 0;
        cacheBits = 0;
        int start = off;

        // ---- frame header
        int sync = bits(14);
        if (sync != 0x3FFE) throw new IOException("no FLAC sync");
        if (bits(1) != 0) throw new IOException("reserved bit");
        bits(1); // blocking strategy
        int bsCode = bits(4);
        int srCode = bits(4);
        int chCode = bits(4);
        int bpsCode = bits(3);
        if (bits(1) != 0) throw new IOException("reserved bit");
        // the frame or sample number, a UTF-8 style number of 1 to 7 bytes
        int first = bits(8);
        int more;
        if (first < 0x80) more = 0;
        else if (first >= 0xC0 && first < 0xE0) more = 1;
        else if (first >= 0xE0 && first < 0xF0) more = 2;
        else if (first >= 0xF0 && first < 0xF8) more = 3;
        else if (first >= 0xF8 && first < 0xFC) more = 4;
        else if (first >= 0xFC && first < 0xFE) more = 5;
        else if (first == 0xFE) more = 6;
        else throw new IOException("bad frame number");
        for (int i = 0; i < more; i++) bits(8);

        int blockSize;
        switch (bsCode) {
            case 0: throw new IOException("reserved block size");
            case 1: blockSize = 192; break;
            case 2: case 3: case 4: case 5: blockSize = 576 << (bsCode - 2); break;
            case 6: blockSize = bits(8) + 1; break;
            case 7: blockSize = bits(16) + 1; break;
            default: blockSize = 256 << (bsCode - 8); break;
        }
        int rate;
        switch (srCode) {
            case 0: rate = streamRate; break;
            case 1: rate = 88200; break;
            case 2: rate = 176400; break;
            case 3: rate = 192000; break;
            case 4: rate = 8000; break;
            case 5: rate = 16000; break;
            case 6: rate = 22050; break;
            case 7: rate = 24000; break;
            case 8: rate = 32000; break;
            case 9: rate = 44100; break;
            case 10: rate = 48000; break;
            case 11: rate = 96000; break;
            case 12: rate = bits(8) * 1000; break;
            case 13: rate = bits(16); break;
            case 14: rate = bits(16) * 10; break;
            default: throw new IOException("bad sample rate code");
        }
        int bps;
        switch (bpsCode) {
            case 0: bps = streamBps; break;
            case 1: bps = 8; break;
            case 2: bps = 12; break;
            case 4: bps = 16; break;
            case 5: bps = 20; break;
            case 6: bps = 24; break;
            case 7: bps = 32; break;
            default: throw new IOException("bad sample size code");
        }
        int channels, assign; // assign: 0 independent, 1 left/side, 2 side/right, 3 mid/side
        if (chCode <= 7) { channels = chCode + 1; assign = 0; }
        else if (chCode <= 10) { channels = 2; assign = chCode - 7; }
        else throw new IOException("bad channel code");
        bits(8); // header CRC-8 (the container already found the frame, so it is not re-checked)

        if (blockSize > 65535) throw new IOException("block too large");
        for (int c = 0; c < channels; c++) if (ch[c] == null || ch[c].length < blockSize) ch[c] = new int[blockSize];
        if (resid.length < blockSize) resid = new int[blockSize];

        // ---- subframes
        for (int c = 0; c < channels; c++) {
            int sb = bps;
            if ((assign == 1 && c == 1) || (assign == 2 && c == 0) || (assign == 3 && c == 1)) sb++;
            subframe(ch[c], blockSize, sb);
        }
        // ---- undo the stereo coding
        if (assign != 0) {
            int[] a = ch[0], b = ch[1];
            for (int i = 0; i < blockSize; i++) {
                if (assign == 1) { b[i] = a[i] - b[i]; }                  // left/side: right = left - side
                else if (assign == 2) { a[i] = a[i] + b[i]; }             // side/right: left = side + right
                else {                                                     // mid/side
                    int mid = a[i], side = b[i];
                    mid = (mid << 1) | (side & 1);
                    a[i] = (mid + side) >> 1;
                    b[i] = (mid - side) >> 1;
                }
            }
        }
        // ---- end of frame: pad to a byte, then the CRC-16
        cacheBits = 0;
        cache = 0;
        bytePos += 2;
        if (bytePos > end) throw new IOException("frame cut short");
        lastConsumed = bytePos - start;
        lastBlockSize = blockSize;
        lastChannels = channels;
        lastSampleRate = rate;
        lastBps = bps;

        // ---- write PCM, interleaved, little-endian, at the output size
        int shift = outBytes * 8 - bps;
        if (shift < 0) throw new IOException("output too small");
        int before = out.position();
        out.order(ByteOrder.LITTLE_ENDIAN);
        for (int i = 0; i < blockSize; i++) {
            for (int c = 0; c < channels; c++) {
                int v = ch[c][i] << shift;
                if (outBytes == 2) out.putShort((short) v);
                else if (outBytes == 3) { out.put((byte) v); out.put((byte) (v >> 8)); out.put((byte) (v >> 16)); }
                else out.putInt(v);
            }
        }
        return out.position() - before;
    }

    private void subframe(int[] o, int n, int bps) throws IOException {
        if (bits(1) != 0) throw new IOException("bad subframe");
        int type = bits(6);
        int wasted = 0;
        if (bits(1) == 1) {
            wasted = 1;
            while (bits(1) == 0) wasted++;
        }
        int sb = bps - wasted;
        if (sb <= 0 || sb > 33) throw new IOException("bad sample size");
        if (type == 0) {
            int v = sbits(sb);
            for (int i = 0; i < n; i++) o[i] = v;
        } else if (type == 1) {
            for (int i = 0; i < n; i++) o[i] = sbits(sb);
        } else if (type >= 8 && type <= 12) {
            int order = type - 8;
            if (order > n) throw new IOException("order too large");
            for (int i = 0; i < order; i++) o[i] = sbits(sb);
            residual(n, order);
            for (int i = order; i < n; i++) {
                long p;
                switch (order) {
                    case 0: p = 0; break;
                    case 1: p = o[i - 1]; break;
                    case 2: p = 2L * o[i - 1] - o[i - 2]; break;
                    case 3: p = 3L * o[i - 1] - 3L * o[i - 2] + o[i - 3]; break;
                    default: p = 4L * o[i - 1] - 6L * o[i - 2] + 4L * o[i - 3] - o[i - 4]; break;
                }
                o[i] = (int) (p + resid[i]);
            }
        } else if (type >= 32) {
            int order = type - 31;
            if (order > n) throw new IOException("order too large");
            for (int i = 0; i < order; i++) o[i] = sbits(sb);
            int prec = bits(4) + 1;
            if (prec == 16) throw new IOException("bad precision");
            int shift = sbits(5);
            if (shift < 0) throw new IOException("negative shift");
            int[] coef = new int[order];
            for (int i = 0; i < order; i++) coef[i] = sbits(prec);
            residual(n, order);
            for (int i = order; i < n; i++) {
                long sum = 0;
                for (int j = 0; j < order; j++) sum += (long) coef[j] * o[i - 1 - j];
                o[i] = (int) ((sum >> shift) + resid[i]);
            }
        } else {
            throw new IOException("reserved subframe type");
        }
        if (wasted > 0) for (int i = 0; i < n; i++) o[i] <<= wasted;
    }

    private void residual(int n, int order) throws IOException {
        int method = bits(2);
        if (method > 1) throw new IOException("bad residual method");
        int pbits = method == 0 ? 4 : 5;
        int escape = method == 0 ? 15 : 31;
        int porder = bits(4);
        int parts = 1 << porder;
        if ((n >> porder) < order) throw new IOException("bad partition");
        int idx = order;
        for (int p = 0; p < parts; p++) {
            int cnt = (n >> porder) - (p == 0 ? order : 0);
            if (cnt < 0) throw new IOException("bad partition size");
            int k = bits(pbits);
            if (k == escape) {
                int raw = bits(5);
                for (int i = 0; i < cnt; i++) resid[idx++] = raw == 0 ? 0 : sbits(raw);
            } else {
                for (int i = 0; i < cnt; i++) {
                    int q = 0;
                    while (bits(1) == 0) {
                        q++;
                        if (q > 1 << 24) throw new IOException("bad Rice code");
                    }
                    long v = ((long) q << k) | (k == 0 ? 0 : bitsLong(k));
                    resid[idx++] = (int) ((v >>> 1) ^ -(v & 1));
                }
            }
        }
    }

    // ------------------------------------------------------------------------------------------------ bit reading
    private int bits(int n) throws IOException {
        if (n == 0) return 0;
        return (int) bitsLong(n);
    }

    private long bitsLong(int n) throws IOException {
        while (cacheBits < n) {
            if (bytePos >= end) throw new IOException("frame cut short");
            cache = (cache << 8) | (buf[bytePos++] & 255);
            cacheBits += 8;
        }
        cacheBits -= n;
        long v = (cache >>> cacheBits) & ((1L << n) - 1);
        cache &= (1L << cacheBits) - 1;
        return v;
    }

    /** A signed value of n bits (n up to 33). */
    private int sbits(int n) throws IOException {
        long v = bitsLong(n);
        long sign = 1L << (n - 1);
        return (int) ((v ^ sign) - sign);
    }
}

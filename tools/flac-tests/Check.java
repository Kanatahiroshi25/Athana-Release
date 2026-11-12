import com.athana.lossless.AthanaFlac;
import java.io.*;
import java.nio.*;
import java.nio.file.*;

public class Check {
    public static void main(String[] a) throws Exception {
        byte[] f = Files.readAllBytes(Paths.get(a[0]));
        byte[] ref = Files.readAllBytes(Paths.get(a[1]));
        int o = 4;
        AthanaFlac.Info info = null;
        while (true) {
            int h = f[o] & 255; int len = (f[o+1]&255)<<16 | (f[o+2]&255)<<8 | (f[o+3]&255);
            if ((h & 0x7F) == 0) info = AthanaFlac.parseStreamInfo(java.util.Arrays.copyOfRange(f, o, o + 4 + len));
            o += 4 + len;
            if ((h & 0x80) != 0) break;
        }
        // also test the form with the marker
        AthanaFlac.Info i2 = AthanaFlac.parseStreamInfo(java.util.Arrays.copyOfRange(f, 0, 4 + 4 + 34));
        if (i2 == null || i2.sampleRate != info.sampleRate || i2.channels != info.channels || i2.bitsPerSample != info.bitsPerSample) throw new RuntimeException("marker form differs");
        AthanaFlac d = new AthanaFlac(info.bitsPerSample, info.sampleRate);
        ByteBuffer out = ByteBuffer.allocate(8 << 20);
        ByteArrayOutputStream all = new ByteArrayOutputStream();
        long t0 = System.nanoTime();
        int frames = 0;
        while (o < f.length) {
            out.clear();
            int n = d.decodeFrame(f, o, f.length - o, out, info.outBytes());
            all.write(out.array(), 0, n);
            o += d.lastConsumed;
            frames++;
        }
        long ms = (System.nanoTime() - t0) / 1000000;
        byte[] got = all.toByteArray();
        boolean same = got.length == ref.length;
        int bad = -1;
        if (same) for (int i = 0; i < got.length; i++) if (got[i] != ref[i]) { same = false; bad = i; break; }
        System.out.println((same ? "OK  " : "FAIL") + " " + a[0] + " rate=" + info.sampleRate + " ch=" + info.channels + " bps=" + info.bitsPerSample + " frames=" + frames + " bytes=" + got.length + "/" + ref.length + " " + ms + "ms" + (bad >= 0 ? " firstDiff=" + bad : ""));
        if (!same) System.exit(1);
    }
}

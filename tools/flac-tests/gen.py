import numpy as np, subprocess, wave, struct, os
os.makedirs('t', exist_ok=True)
rng = np.random.default_rng(1)

def write_wav(path, data, rate, bits):
    # data: int array (n, ch) in the range of 'bits'
    n, ch = data.shape
    if bits == 24:
        b = bytearray()
        for v in data.reshape(-1):
            v = int(v) & 0xFFFFFF
            b += bytes((v & 255, (v >> 8) & 255, (v >> 16) & 255))
        raw = bytes(b)
    elif bits == 16:
        raw = data.astype('<i2').tobytes()
    elif bits == 8:
        raw = (data.astype(np.int16) + 128).astype('u1').tobytes()
    with wave.open(path, 'wb') as w:
        w.setnchannels(ch); w.setsampwidth(bits // 8); w.setframerate(rate); w.writeframes(raw)

def music(n, ch, rate, bits, kind='mix'):
    t = np.arange(n) / rate
    full = 2 ** (bits - 1) - 1
    out = []
    for c in range(ch):
        if kind == 'mix':
            x = 0.4 * np.sin(2 * np.pi * (220 + 40 * c) * t) + 0.25 * np.sin(2 * np.pi * (3300 + 100 * c) * t * (1 + 0.1 * np.sin(t * 3)))
            x += 0.05 * rng.standard_normal(n)
        elif kind == 'noise':
            x = rng.uniform(-1, 1, n)
        elif kind == 'silence':
            x = np.zeros(n)
        elif kind == 'square':
            x = np.sign(np.sin(2 * np.pi * 100 * t)) * 0.9
        elif kind == 'clip':
            x = np.clip(2.5 * np.sin(2 * np.pi * 440 * t), -1, 1)
        out.append(np.clip(x, -1, 1))
    d = (np.stack(out, 1) * full).astype(np.int64)
    return d

cases = [
    # name, rate, ch, bits, kind, seconds, ffmpeg flac options
    ('s16_44k_lvl0', 44100, 2, 16, 'mix', 6, '-compression_level 0'),
    ('s16_44k_lvl5', 44100, 2, 16, 'mix', 6, '-compression_level 5'),
    ('s16_44k_lvl8', 44100, 2, 16, 'mix', 6, '-compression_level 8'),
    ('s16_44k_lvl12', 44100, 2, 16, 'mix', 6, '-compression_level 12'),
    ('s16_mono', 44100, 1, 16, 'mix', 5, '-compression_level 8'),
    ('s16_noise', 44100, 2, 16, 'noise', 4, '-compression_level 8'),
    ('s16_silence', 44100, 2, 16, 'silence', 3, '-compression_level 8'),
    ('s16_square', 48000, 2, 16, 'square', 4, '-compression_level 8'),
    ('s16_clip', 48000, 2, 16, 'clip', 4, '-compression_level 8'),
    ('s16_8k_small', 8000, 1, 16, 'mix', 5, '-compression_level 8 -frame_size 16'),
    ('s16_bigframes', 44100, 2, 16, 'mix', 6, '-compression_level 8 -frame_size 4608'),
    ('s16_6ch', 48000, 6, 16, 'mix', 4, '-compression_level 8'),
    ('s16_8ch', 48000, 8, 16, 'mix', 3, '-compression_level 5'),
    ('s24_96k', 96000, 2, 24, 'mix', 6, '-compression_level 8'),
    ('s24_192k', 192000, 2, 24, 'mix', 4, '-compression_level 8'),
    ('s24_noise', 96000, 2, 24, 'noise', 3, '-compression_level 8'),
    ('s24_mono', 88200, 1, 24, 'mix', 3, '-compression_level 12'),
    ('s8_u8', 22050, 2, 8, 'mix', 3, '-compression_level 8'),
]
for name, rate, ch, bits, kind, sec, opt in cases:
    n = rate * sec
    d = music(n, ch, rate, bits, kind)
    if bits == 24 and name == 's24_mono': pass
    write_wav(f't/{name}.wav', d, rate, bits)
# wasted bits: 16-bit samples whose low 4 bits are zero, and 24-bit with low 8 zero
d = music(44100 * 4, 2, 44100, 16, 'mix') & ~0xF
write_wav('t/s16_wasted.wav', d, 44100, 16)
d = music(96000 * 3, 2, 96000, 24, 'mix') & ~0xFF
write_wav('t/s24_wasted.wav', d, 96000, 24)
# stereo modes: identical channels (side=0), opposite channels, one silent channel
m = music(44100 * 4, 1, 44100, 16, 'mix')
write_wav('t/s16_dual_same.wav', np.hstack([m, m]), 44100, 16)
write_wav('t/s16_dual_inv.wav', np.hstack([m, -m]), 44100, 16)
write_wav('t/s16_dual_oneside.wav', np.hstack([m, np.zeros_like(m)]), 44100, 16)
# extremes
x = np.array([[-32768, 32767]] * 5000 + [[32767, -32768]] * 5000, dtype=np.int64)
write_wav('t/s16_extreme.wav', x, 44100, 16)
x = np.array([[-8388608, 8388607]] * 5000 + [[8388607, -8388608]] * 5000, dtype=np.int64)
write_wav('t/s24_extreme.wav', x, 44100, 24)

opts = {c[0]: c[6] for c in cases}
for f in sorted(os.listdir('t')):
    if not f.endswith('.wav'): continue
    name = f[:-4]
    opt = opts.get(name, '-compression_level 8')
    bits = 24 if name.startswith('s24') else (8 if name.startswith('s8') else 16)
    codec = ['-c:a', 'flac']
    sf = 's32' if bits == 24 else 's16'
    cmd = ['ffmpeg', '-v', 'error', '-y', '-i', f't/{f}', '-c:a', 'flac', '-sample_fmt', sf] + (['-bits_per_raw_sample', '24'] if bits == 24 else []) + opt.split() + [f't/{name}.flac']
    subprocess.run(cmd, check=True)
    # reference decode by ffmpeg: s16le for <=16 bit, s24le for 24 bit
    out_fmt = 's24le' if bits == 24 else 's16le'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', f't/{name}.flac', '-f', out_fmt, '-acodec', 'pcm_' + out_fmt, f't/{name}.raw'], check=True)
print('done', len([x for x in os.listdir('t') if x.endswith('.flac')]), 'flac files')

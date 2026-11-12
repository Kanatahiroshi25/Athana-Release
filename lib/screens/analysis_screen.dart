import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../design.dart';
import '../models.dart';
import '../native.dart';
import '../widgets.dart';

/// "Analyse song": a spectrogram, a check for fake hi-res, real bit depth, loudness, peak, clipping and dynamic range.
/// The same measurements as the web version's Analyze tab.
class AnalysisScreen extends StatefulWidget {
  final AppState state;
  const AnalysisScreen({super.key, required this.state});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  AppState get s => widget.state;
  bool _running = false;
  String _status = '';
  Track? _for; // the song the shown result belongs to
  Map<String, dynamic>? _res;
  ui.Image? _img;

  // the colour ramp of the web version's spectrogram
  static final List<List<int>> _lut = _makeLut();
  static List<List<int>> _makeLut() {
    const st = <List<num>>[
      [0, 0, 0, 4],
      [.19, 59, 15, 112],
      [.38, 140, 41, 129],
      [.57, 222, 73, 104],
      [.76, 254, 159, 109],
      [1, 252, 253, 191],
    ];
    final out = <List<int>>[];
    for (var i = 0; i < 256; i++) {
      final t = i / 255;
      var k = 1;
      while (k < st.length - 1 && t > st[k][0]) {
        k++;
      }
      final a = st[k - 1], b = st[k];
      final u = (t - a[0]) / (b[0] - a[0]);
      out.add([for (var j = 1; j <= 3; j++) (a[j] + (b[j] - a[j]) * u).round()]);
    }
    return out;
  }

  @override
  void dispose() {
    if (_running) Native.analyzeCancel();
    _img?.dispose();
    super.dispose();
  }

  Future<ui.Image> _spectrogram(Uint8List b, int cols, int h) {
    final px = Uint8List(cols * h * 4);
    for (var x = 0; x < cols; x++) {
      for (var k = 0; k < h; k++) {
        final c = _lut[b[x * h + k]];
        final o = ((h - 1 - k) * cols + x) * 4; // high pitch at the top
        px[o] = c[0];
        px[o + 1] = c[1];
        px[o + 2] = c[2];
        px[o + 3] = 255;
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, cols, h, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  Future<void> _run() async {
    final t = s.current;
    if (t == null) {
      setState(() => _status = 'Play a song first.');
      return;
    }
    if (_running) return;
    s.anProgress.value = 0;
    setState(() {
      _running = true;
      _status = 'Reading the song…';
      _res = null;
      _for = null;
      _img?.dispose();
      _img = null;
    });
    try {
      final r = await Native.analyze(t);
      if (!mounted) return;
      if (r == null) {
        setState(() => _status = 'This file could not be analysed.');
        return;
      }
      ui.Image? img;
      final cols = (r['cols'] ?? 0) as int;
      if (cols > 0) img = await _spectrogram(r['spec'] as Uint8List, cols, (r['h'] ?? 1024) as int);
      s.analysisSave(t, r);
      if (!mounted) {
        img?.dispose();
        return;
      }
      setState(() {
        _res = r;
        _for = t;
        _img = img;
        _status = '';
      });
    } on PlatformException catch (e) {
      final why = (e.code == 'analysis' && (e.message ?? '').isNotEmpty && e.message != 'unknown') ? ' (${e.message})' : '';
      if (mounted) setState(() => _status = 'This file could not be analysed.$why');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: ListenableBuilder(
        listenable: s,
        builder: (BuildContext context, Widget? _) {
          final accent = accentOf(s);
          final t = s.current;
          // show the result of the song that is playing: the fresh one, or the numbers saved earlier
          Map<String, dynamic>? res;
          var fresh = false;
          if (t != null) {
            if (identical(_for, t) && _res != null) {
              res = _res;
              fresh = true;
            } else {
              res = s.analysisCached(t);
            }
          }
          return Backdrop(
            accent: accent,
            child: SafeArea(
              child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 16, 2),
                  child: Row(children: [
                    IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 4),
                    const Expanded(child: Text('Analyse song', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
                  ]),
                ),
                if (t != null) _songCard(t),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Cta(
                    label: _running ? 'Analysing…' : (res == null ? 'Analyse current song' : 'Analyse again'),
                    icon: Icons.graphic_eq_rounded,
                    accent: accent,
                    onTap: (_running || t == null) ? null : _run,
                  ),
                ),
                if (_running)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: ValueListenableBuilder<double>(
                      valueListenable: s.anProgress,
                      builder: (BuildContext c, double p, Widget? w) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: p <= 0 ? null : p, minHeight: 6, color: lighter(accent), backgroundColor: Colors.white.withAlpha(20))),
                        const SizedBox(height: 8),
                        Text(p <= 0 ? 'Starting…' : 'Reading the song, ${(p * 100).round()}%', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(140))),
                      ]),
                    ),
                  ),
                if (_status.isNotEmpty && !_running)
                  Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Text(_status, style: TextStyle(color: Colors.white.withAlpha(170)))),
                if (t == null)
                  Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0), child: Text('Play a song, then come back here.', style: TextStyle(color: Colors.white.withAlpha(140)))),
                if (res != null && !_running) ...[
                  if (fresh && _img != null) _specCard(_img!, res),
                  if (!fresh)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Text('Measured earlier. Analyse again to see the spectrogram.', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(120))),
                    ),
                  _verdict(res),
                  _grid(res),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Text(
                      'Bandwidth and bit depth are estimates from the audio itself. DR is an approximation, not the official TT-DR meter.',
                      style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(105)),
                    ),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _songCard(Track t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: glass(),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Cover(path: t.art, size: 52, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                [t.ext.toUpperCase(), if (t.bits > 0) '${t.bits}-bit', if (t.rate > 0) '${(t.rate / 1000).toStringAsFixed(t.rate % 1000 == 0 ? 0 : 1)} kHz'].join(' · '),
                style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(140)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _specCard(ui.Image img, Map<String, dynamic> r) {
    final rate = (r['rate'] ?? 44100) as int;
    final cutoff = ((r['cutoff'] ?? 0) as num).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 640 / 260,
          child: CustomPaint(painter: _SpecPainter(img, rate / 2.0, cutoff)),
        ),
      ),
    );
  }

  Widget _verdict(Map<String, dynamic> r) {
    final rate = (r['rate'] ?? 44100) as int;
    final cutoff = ((r['cutoff'] ?? 0) as num).toDouble();
    final kc = (cutoff / 1000).toStringAsFixed(1);
    var ok = true;
    String msg;
    if (rate <= 48000) {
      if (cutoff < 17500) {
        ok = false;
        msg = 'Content stops near $kc kHz, typical of a lossy (MP3/AAC) source';
      } else {
        msg = 'Full bandwidth, content reaches about $kc kHz';
      }
    } else if (cutoff < 23500) {
      ok = false;
      msg = 'Nothing above $kc kHz. Looks upsampled from a 44.1/48 kHz source';
    } else {
      msg = 'Real hi-res: content reaches about $kc kHz of ${(rate / 2000).toStringAsFixed(1)}';
    }
    final c = ok ? const Color(0xFF66BB6A) : const Color(0xFFFFB74D);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withAlpha(90))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: c, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3))),
        ]),
      ),
    );
  }

  Widget _grid(Map<String, dynamic> r) {
    final lufs = r['lufs'];
    final dr = r['dr'];
    final clip = (r['clip'] ?? 0) as int;
    final bits = (r['bits'] ?? 0) as int;
    final eff = r['eff'];
    final eb = (bits == 0 || eff == null) ? '—' : ((eff as int) < bits ? '$eff-bit (padded to $bits)' : '$bits-bit');
    final cells = <(String, String)>[
      (lufs == null ? '—' : '${(lufs as num).toStringAsFixed(1)} LUFS', 'Loudness'),
      ('${((r['peak'] ?? -120) as num).toStringAsFixed(1)} dBFS', 'Peak'),
      (dr == null ? '—' : 'DR ${(dr as num).toStringAsFixed(1)}', 'Dynamic range (estimate)'),
      (clip > 0 ? '$clip spots' : 'None', 'Clipping'),
      (eb, 'Real bit depth'),
      ('${(((r['cutoff'] ?? 0) as num) / 1000).toStringAsFixed(1)} kHz', 'Bandwidth'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (final c in cells)
          Container(
            width: (MediaQuery.of(context).size.width - 32 - 10) / 2,
            padding: const EdgeInsets.all(14),
            decoration: glass(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.$1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(c.$2, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(130))),
            ]),
          ),
      ]),
    );
  }
}

/// The picture, with a pitch scale on the left and a dashed line where the content stops.
class _SpecPainter extends CustomPainter {
  final ui.Image img;
  final double nyq, cutoff;
  _SpecPainter(this.img, this.nyq, this.cutoff);

  void _label(Canvas canvas, String text, Offset at, Color color) {
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(fontSize: 11, color: color)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    paintImage(canvas: canvas, rect: rect, image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
    final step = nyq > 30000 ? 10000.0 : 5000.0;
    final line = Paint()
      ..color = Colors.white.withAlpha(50)
      ..strokeWidth = 1;
    for (var f = 0.0; f <= nyq; f += step) {
      final y = size.height - f / nyq * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      _label(canvas, '${(f / 1000).round()} kHz', Offset(6, (y - 14).clamp(0.0, size.height - 14)), Colors.white.withAlpha(230));
    }
    if (cutoff > 0) {
      final y = size.height - cutoff / nyq * size.height;
      final dash = Paint()
        ..color = const Color(0xFFFBBF24)
        ..strokeWidth = 1.6;
      for (var x = 0.0; x < size.width; x += 10) {
        canvas.drawLine(Offset(x, y), Offset((x + 6).clamp(0.0, size.width), y), dash);
      }
      _label(canvas, '~${(cutoff / 1000).toStringAsFixed(1)} kHz', Offset(size.width - 74, (y - 16).clamp(0.0, size.height - 14)), const Color(0xFFFBBF24));
    }
  }

  @override
  bool shouldRepaint(_SpecPainter o) => o.img != img || o.cutoff != cutoff || o.nyq != nyq;
}

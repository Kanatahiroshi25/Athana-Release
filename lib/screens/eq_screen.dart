import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../design.dart';
import '../eq_presets.dart';
import 'mixer_panel.dart';
import '../widgets.dart';

/// The equalizer: ten bands, a preamp and lots of starting points.
/// The curve you see is the real response of the filters the player uses.
class EqScreen extends StatefulWidget {
  final AppState state;
  const EqScreen({super.key, required this.state});

  @override
  State<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends State<EqScreen> {
  // While a finger is on the bars the page must not scroll.
  final ValueNotifier<bool> _lock = ValueNotifier<bool>(false);
  int _tab = 0; // 0 equalizer, 1 mixer

  AppState get s => widget.state;

  @override
  void dispose() {
    _lock.dispose();
    super.dispose();
  }

  String _db(double v) => (v > 0 ? '+' : '') + v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: ListenableBuilder(
        listenable: s,
        builder: (BuildContext context, Widget? _) {
          final accent = accentOf(s);
          final p = s.prefs;
          return Backdrop(
            accent: accent,
            child: SafeArea(
              child: ValueListenableBuilder<bool>(
                valueListenable: _lock,
                builder: (BuildContext context, bool locked, Widget? _) => ListView(
                  physics: locked ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    _topBar(context, accent),
                    _tabs(accent),
                    if (_tab == 1)
                      MixerPanel(s: s, accent: accent, lock: _lock)
                    else ...[
                      _statusCard(accent),
                      _plotCard(accent),
                      _strengthCard(accent),
                      _preampCard(accent),
                      for (final e in kEqGroups.entries) ...[
                        SectionLabel(e.key),
                        _presetWrap(accent, [for (final pr in e.value) pr.name]),
                      ],
                      const SectionLabel('My presets'),
                      _mine(context, accent),
                      const SizedBox(height: 18),
                      _footnote(p.eqOn),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _topBar(BuildContext context, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 2),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 4),
        Expanded(child: Text(_tab == 1 ? 'Mixer' : 'Equalizer', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
        TextButton.icon(
          onPressed: () {
            if (_tab == 1) {
              s.mixReset();
              toast(context, 'Mixer reset');
            } else {
              s.eqReset();
              toast(context, 'Back to flat');
            }
          },
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('Reset'),
        ),
      ]),
    );
  }

  /// Equalizer | Mixer, as a rounded switch under the title.
  Widget _tabs(Color accent) {
    Widget item(int i, IconData icon, String label, bool lit) {
      final sel = _tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _tab = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(color: sel ? Colors.white.withAlpha(22) : Colors.transparent, borderRadius: BorderRadius.circular(22)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 21, color: sel ? Colors.white : Colors.white.withAlpha(130)),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: sel ? Colors.white : Colors.white.withAlpha(130))),
              if (lit) Padding(padding: const EdgeInsets.only(left: 7), child: Container(width: 7, height: 7, decoration: BoxDecoration(color: lighter(accent), shape: BoxShape.circle))),
            ]),
          ),
        ),
      );
    }

    final out = s.prefs.autoOut && s.outLabel.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.headphones_rounded, size: 14, color: lighter(accent)),
              const SizedBox(width: 6),
              Flexible(child: Text('Saved for: ${s.outLabel}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(150)))),
            ]),
          )
        : const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(children: [
        out,
        Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(26), border: Border.all(color: Colors.white.withAlpha(18))),
        child: Row(children: [
          item(0, Icons.equalizer_rounded, 'Equalizer', s.prefs.eqOn),
          item(1, Icons.tune_rounded, 'Mixer', !s.mixIsDefault || s.speed != 1.0),
        ]),
      ),
      ]),
    );
  }

  Widget _statusCard(Color accent) {
    final p = s.prefs;
    final on = p.eqOn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: glass(),
        padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: (on ? accent : Colors.white).withAlpha(on ? 70 : 20), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.equalizer_rounded, color: on ? lighter(accent) : Colors.white.withAlpha(150)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(on ? 'Equalizer on' : 'Equalizer off', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(on ? 'Preset: ${p.eqPreset}${p.eqStrength == 100 ? '' : '  ·  ${p.eqStrength.round()}%'}' : 'Music plays untouched, bit-perfect', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(140))),
            ]),
          ),
          Switch(value: on, onChanged: (bool v) => s.eqSetOn(v)),
        ]),
      ),
    );
  }

  Widget _plotCard(Color accent) {
    final p = s.prefs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: glass(),
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
        child: Column(children: [
          Row(children: [
            for (var i = 0; i < 10; i++)
              Expanded(
                child: Text(
                  _db(p.eqGains[i]),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.eqGains[i] == 0 ? Colors.white.withAlpha(110) : lighter(accent)),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          _EqPlot(state: s, lock: _lock, accent: accent),
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 0; i < 10; i++)
              Expanded(child: Text(kEqLabels[i], textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(150)))),
          ]),
          const SizedBox(height: 4),
          Text('Drag a bar  ·  double-tap to reset it', style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(95))),
        ]),
      ),
    );
  }

  Widget _strengthCard(Color accent) {
    final p = s.prefs;
    final can = s.eqCanScale;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: glass(),
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Strength', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('${p.eqStrength.round()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: can ? lighter(accent) : Colors.white.withAlpha(90))),
            ),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white.withAlpha(30),
              thumbColor: lighter(accent),
              overlayColor: accent.withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(
              value: p.eqStrength,
              min: 50,
              max: 200,
              divisions: 30,
              onChanged: can ? (double v) => s.eqSetStrength(v, save: false) : null,
              onChangeEnd: can ? (double v) => s.eqSetStrength(v) : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              !can
                  ? 'Choose a preset below, then make it softer or stronger here.'
                  : (s.eqLimited ? 'Softer  ·  100% = as designed  ·  Stronger. Some bands have reached the ±12 dB limit.' : 'Softer  ·  100% = as designed  ·  Stronger'),
              style: TextStyle(fontSize: 12, color: s.eqLimited ? const Color(0xFFFFB74D) : Colors.white.withAlpha(105)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _preampCard(Color accent) {
    final p = s.prefs;
    final eff = s.eqEffectivePre;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: glass(),
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Preamp', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('${_db(p.eqPre)} dB', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: lighter(accent))),
            ),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white.withAlpha(30),
              thumbColor: lighter(accent),
              overlayColor: accent.withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(
              value: p.eqPre,
              min: -12,
              max: 12,
              divisions: 48,
              onChanged: (double v) => s.eqSetPre(v, save: false),
              onChangeEnd: (double v) => s.eqSetPre(v),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(right: 4),
            dense: true,
            title: const Text('Prevent clipping', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              p.eqAuto
                  ? 'Lowers the volume a little when you boost, so loud songs stay clean. Now: ${_db(eff)} dB'
                  : 'Off: loud songs may distort when you boost a lot',
              style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(120)),
            ),
            value: p.eqAuto,
            onChanged: (bool v) => s.eqSetAuto(v),
          ),
        ]),
      ),
    );
  }

  Widget _presetWrap(Color accent, List<String> names) {
    final cur = s.prefs.eqPreset;
    final on = s.prefs.eqOn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final n in names)
          PillChoice(
            label: n,
            selected: on && cur == n,
            accent: accent,
            onTap: () {
              HapticFeedback.selectionClick();
              s.eqChoose(n);
            },
          ),
      ]),
    );
  }

  Widget _mine(BuildContext context, Color accent) {
    final cur = s.prefs.eqPreset;
    final on = s.prefs.eqOn;
    final names = s.prefs.myEq.keys.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final n in names)
            GestureDetector(
              onLongPress: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext d) => AlertDialog(
                    title: Text('Delete "$n"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) s.eqDeleteMine(n);
              },
              child: PillChoice(label: n, selected: on && cur == n, accent: accent, onTap: () => s.eqChoose(n)),
            ),
          PillChoice(
            label: '+ Save current',
            selected: false,
            accent: accent,
            onTap: () async {
              final n = await askName(context, 'Name this sound');
              if (n == null || n.trim().isEmpty) return;
              s.eqSaveMine(n);
              if (context.mounted) toast(context, 'Saved "${n.trim()}"');
            },
          ),
        ]),
        if (names.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Press and hold one to delete it.', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(95))),
        ],
      ]),
    );
  }

  Widget _footnote(bool on) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Text(
        'While the equalizer is on, Athana processes the sound in 16-bit with a tiny amount of dither, which you cannot hear. '
        'Turn it off and your files play exactly as they are, with nothing changed. '
        'Switching it on or off restarts the current song for a moment, at the same place.',
        style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.white.withAlpha(105)),
      ),
    );
  }
}

/// The ten bars with the response curve drawn behind them. A finger on a column moves that band.
class _EqPlot extends StatefulWidget {
  final AppState state;
  final ValueNotifier<bool> lock;
  final Color accent;
  const _EqPlot({required this.state, required this.lock, required this.accent});

  @override
  State<_EqPlot> createState() => _EqPlotState();
}

class _EqPlotState extends State<_EqPlot> {
  static const double kHeight = 240;
  static const double kPad = 16;

  int? _band;
  int _lastBand = -1;
  int _lastDownMs = 0;
  bool _changed = false;

  AppState get s => widget.state;

  double _dbAt(double y) {
    final t = ((y - kPad) / (kHeight - 2 * kPad)).clamp(0.0, 1.0);
    final v = 12 - t * 24;
    return (v * 2).round() / 2;
  }

  int _bandAt(double x, double w) => (x / w * 10).floor().clamp(0, 9);

  void _set(int i, double db) {
    if (s.prefs.eqGains[i] == db && s.prefs.eqOn) return;
    _changed = true;
    if (s.prefs.haptic) HapticFeedback.selectionClick();
    s.eqSetBand(i, db, save: false);
  }

  @override
  Widget build(BuildContext context) {
    final p = s.prefs;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final w = c.maxWidth;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (PointerDownEvent e) {
          widget.lock.value = true;
          final i = _bandAt(e.localPosition.dx, w);
          final now = DateTime.now().millisecondsSinceEpoch;
          _band = i;
          if (_lastBand == i && now - _lastDownMs < 320) {
            _set(i, 0);
          } else {
            _set(i, _dbAt(e.localPosition.dy));
          }
          _lastBand = i;
          _lastDownMs = now;
          setState(() {});
        },
        onPointerMove: (PointerMoveEvent e) {
          final i = _band;
          if (i == null) return;
          _set(i, _dbAt(e.localPosition.dy));
        },
        onPointerUp: (PointerUpEvent e) => _end(),
        onPointerCancel: (PointerCancelEvent e) => _end(),
        child: SizedBox(
          height: kHeight,
          width: w,
          child: CustomPaint(
            painter: _PlotPainter(gains: List<double>.of(p.eqGains), accent: widget.accent, on: p.eqOn, active: _band),
          ),
        ),
      );
    });
  }

  void _end() {
    widget.lock.value = false;
    if (_changed) s.savePrefs();
    _changed = false;
    setState(() => _band = null);
  }
}

class _PlotPainter extends CustomPainter {
  final List<double> gains;
  final Color accent;
  final bool on;
  final int? active;
  _PlotPainter({required this.gains, required this.accent, required this.on, required this.active});

  static const double kPad = _EqPlotState.kPad;

  double _y(double db, double h) => kPad + (12 - db) / 24 * (h - 2 * kPad);

  /// Response of one peaking filter (RBJ) at frequency f, in dB. Same maths as the player.
  static double _peak(double f0, double gDb, double f) {
    if (gDb == 0) return 0;
    const fs = 48000.0;
    const q = 1.1;
    final a = math.pow(10, gDb / 40).toDouble();
    final w0 = 2 * math.pi * f0 / fs;
    final al = math.sin(w0) / (2 * q);
    final cw = math.cos(w0);
    final b0 = 1 + al * a, b1 = -2 * cw, b2 = 1 - al * a;
    final a0 = 1 + al / a, a1 = -2 * cw, a2 = 1 - al / a;
    final w = 2 * math.pi * f / fs;
    final c1 = math.cos(w), c2 = math.cos(2 * w);
    final num = b0 * b0 + b1 * b1 + b2 * b2 + 2 * (b0 * b1 + b1 * b2) * c1 + 2 * b0 * b2 * c2;
    final den = a0 * a0 + a1 * a1 + a2 * a2 + 2 * (a0 * a1 + a1 * a2) * c1 + 2 * a0 * a2 * c2;
    return 10 * (math.log(num / den) / math.ln10);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final colW = w / 10;
    final k = on ? 1.0 : 0.38;
    int al(int a) => (a * k).round().clamp(0, 255);

    // grid
    final grid = Paint()..strokeWidth = 1;
    for (final db in const [12.0, 6.0, 0.0, -6.0, -12.0]) {
      final y = _y(db, h);
      grid.color = Colors.white.withAlpha(db == 0 ? 46 : 16);
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
    for (final db in const [12.0, 0.0, -12.0]) {
      final tp = TextPainter(
        text: TextSpan(text: db > 0 ? '+${db.toInt()}' : '${db.toInt()}', style: TextStyle(fontSize: 9, color: Colors.white.withAlpha(70))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(3, _y(db, h) - tp.height - 1));
    }

    final zero = _y(0, h);

    // the bars
    for (var i = 0; i < 10; i++) {
      final cx = colW * (i + 0.5);
      final isActive = active == i;
      final track = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, h / 2), width: 4, height: h - 2 * kPad + 4), const Radius.circular(2));
      canvas.drawRRect(track, Paint()..color = Colors.white.withAlpha(isActive ? 34 : 20));
      final y = _y(gains[i], h);
      if (gains[i] != 0) {
        final rect = Rect.fromLTRB(cx - 2.5, math.min(y, zero), cx + 2.5, math.max(y, zero));
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2.5)),
          Paint()
            ..shader = LinearGradient(
              begin: gains[i] > 0 ? Alignment.topCenter : Alignment.bottomCenter,
              end: gains[i] > 0 ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [lighter(accent).withAlpha(al(255)), accent.withAlpha(al(150))],
            ).createShader(rect),
        );
      }
    }

    // the curve
    final path = Path();
    final fill = Path();
    const f0 = 31.0;
    var first = true;
    for (double x = 0; x <= w; x += 3) {
      final u = x / colW - 0.5; // band centres are at u = 0..9
      final f = f0 * math.pow(2, u).toDouble();
      var db = 0.0;
      for (var i = 0; i < 10; i++) {
        db += _peak(kEqFreqs[i], gains[i], f);
      }
      final y = _y(db.clamp(-13.0, 13.0), h);
      if (first) {
        path.moveTo(x, y);
        fill.moveTo(x, zero);
        fill.lineTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(w, zero);
    fill.close();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [accent.withAlpha(al(70)), accent.withAlpha(al(10)), accent.withAlpha(al(70))])
            .createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 7..color = accent.withAlpha(al(60))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..color = lighter(accent).withAlpha(al(255)));
    canvas.restore();

    // the handles
    for (var i = 0; i < 10; i++) {
      final cx = colW * (i + 0.5);
      final y = _y(gains[i], h);
      final isActive = active == i;
      if (isActive) canvas.drawCircle(Offset(cx, y), 17, Paint()..color = accent.withAlpha(al(70)));
      canvas.drawCircle(Offset(cx, y), isActive ? 10 : 8, Paint()..color = Colors.white.withAlpha(al(255)));
      canvas.drawCircle(Offset(cx, y), isActive ? 5.5 : 4, Paint()..color = (gains[i] == 0 ? Colors.black.withAlpha(60) : accent).withAlpha(al(255)));
    }
  }

  @override
  bool shouldRepaint(_PlotPainter o) => o.on != on || o.active != active || o.accent != accent || !sameGains(o.gains, gains);
}

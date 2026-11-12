import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../design.dart';
import '../widgets.dart';

/// The "Mixer" tab of the Sound screen: Balance, Stereo Expand, Tempo, Mono and Volume knobs.
/// Drag a knob up or to the right to turn it up. Double-tap a knob to put it back in the middle.
class MixerPanel extends StatelessWidget {
  final AppState s;
  final Color accent;
  final ValueNotifier<bool> lock; // true while a finger is on a knob, so the page does not scroll
  const MixerPanel({super.key, required this.s, required this.accent, required this.lock});

  @override
  Widget build(BuildContext context) {
    final p = s.prefs;
    final bal = p.mixBal;
    final balText = bal == 0 ? 'Centre' : '${bal < 0 ? 'Left' : 'Right'} ${(bal.abs() * 100).round()}%';
    final speed = (s.speed * 100).round() / 100.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _labeled(
            'Balance',
            balText,
            Knob(size: 124, value: bal, min: -1, max: 1, reset: 0, accent: accent, lock: lock, onChanged: (double v) => s.mixChange(bal: v)),
          ),
          _labeled(
            'Stereo Expand',
            '${p.mixWide}%',
            Knob(size: 124, value: p.mixWide.toDouble(), min: 0, max: 100, reset: 0, accent: accent, lock: lock, onChanged: (double v) => s.mixChange(wide: v.round())),
          ),
        ]),
        const SizedBox(height: 22),
        Row(children: [
          const _Tag('Tempo'),
          const Spacer(),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 56),
          Expanded(
            child: Center(
              child: _labeled(
                '',
                '${speed.toStringAsFixed(2)}×',
                Knob(size: 140, value: speed, min: 0.5, max: 2.0, reset: 1.0, accent: accent, lock: lock, onChanged: (double v) => s.setSpeed((v * 100).round() / 100.0)),
              ),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            _StepBtn(icon: Icons.add_rounded, onTap: () { tapFeedback(s); s.setSpeed((((speed + 0.05) * 100).round() / 100.0).clamp(0.5, 2.0).toDouble()); }),
            const SizedBox(height: 10),
            _StepBtn(icon: Icons.remove_rounded, onTap: () { tapFeedback(s); s.setSpeed((((speed - 0.05) * 100).round() / 100.0).clamp(0.5, 2.0).toDouble()); }),
          ]),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Tempo changes the speed and keeps the pitch.', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(100))),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _Tag('Mono', on: p.mixMono, accent: accent, onTap: () { tapFeedback(s); s.mixChange(mono: !p.mixMono); }),
          const Spacer(),
          _Tag('Reset', strong: true, onTap: () { tapFeedback(s); s.mixReset(); toast(context, 'Mixer reset'); }),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          decoration: glass(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Crossfeed', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              Text(p.mixCross == 0 ? 'Off' : '${p.mixCross}%', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(170))),
            ]),
            Slider(
              value: p.mixCross.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              activeColor: lighter(accent),
              onChanged: (double v) => s.mixChange(cross: v.round()),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 4),
              child: Text(
                'For headphones and in-ear monitors. Blends a little of each side, softened and slightly late, into the other ear, like speakers in a room. The music stops feeling stuck inside your head. Use Stereo Expand for the opposite.',
                style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(110)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        _labeled(
          'Volume',
          '${p.mixVol}%',
          Knob(
            size: 164,
            value: p.mixVol.toDouble(),
            min: 0,
            max: 150,
            reset: 100,
            accent: accent,
            lock: lock,
            hotFrom: 100,
            onChanged: (double v) => s.mixChange(vol: v.round()),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Volume here is a trim inside Athana, on top of your phone\'s volume. Above 100% is a boost and may distort loud songs.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(100)),
        ),
        const SizedBox(height: 10),
        Text(
          s.mixIsDefault ? 'All knobs are in the middle, so your music is passed through untouched.' : 'Knobs in use. Reset puts the sound back to untouched.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(100)),
        ),
      ]),
    );
  }

  Widget _labeled(String title, String value, Widget knob) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      knob,
      const SizedBox(height: 10),
      if (title.isNotEmpty) Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(150))),
    ]);
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool on;
  final bool strong;
  final Color? accent;
  final VoidCallback? onTap;
  const _Tag(this.label, {this.on = false, this.strong = false, this.accent, this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = accent ?? Colors.white;
    return Material(
      color: on ? a.withAlpha(60) : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: on ? lighter(a) : Colors.white.withAlpha(strong ? 190 : 80))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: on ? lighter(a) : Colors.white.withAlpha(strong ? 255 : 200))),
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withAlpha(14),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(width: 50, height: 40, child: Icon(icon, size: 20, color: Colors.white.withAlpha(190))),
      ),
    );
  }
}

/// A round knob. Drag up or right to raise it. Double-tap to reset.
class Knob extends StatefulWidget {
  final double size, value, min, max, reset;
  final double? hotFrom; // above this value the ring turns red (a boost)
  final Color accent;
  final ValueNotifier<bool> lock;
  final ValueChanged<double> onChanged;
  const Knob({
    super.key,
    required this.size,
    required this.value,
    required this.min,
    required this.max,
    required this.reset,
    required this.accent,
    required this.lock,
    required this.onChanged,
    this.hotFrom,
  });

  @override
  State<Knob> createState() => _KnobState();
}

class _KnobState extends State<Knob> {
  double? _drag; // the exact value while a finger is down (the shown value is rounded)

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return GestureDetector(
      onDoubleTap: () => w.onChanged(w.reset),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          _drag = w.value;
          w.lock.value = true;
        },
        onPointerUp: (_) {
          _drag = null;
          w.lock.value = false;
        },
        onPointerCancel: (_) {
          _drag = null;
          w.lock.value = false;
        },
        onPointerMove: (PointerMoveEvent e) {
          // 240 pixels of drag sweeps the whole range.
          final d = (e.delta.dx - e.delta.dy) / 240.0 * (w.max - w.min);
          final v = ((_drag ?? w.value) + d).clamp(w.min, w.max).toDouble();
          _drag = v;
          w.onChanged(v);
        },
        child: CustomPaint(
          size: Size.square(w.size),
          painter: _KnobPainter(value: w.value, min: w.min, max: w.max, reset: w.reset, accent: lighter(w.accent), hotFrom: w.hotFrom),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double value, min, max, reset;
  final double? hotFrom;
  final Color accent;
  _KnobPainter({required this.value, required this.min, required this.max, required this.reset, required this.accent, required this.hotFrom});

  // 0 at 7 o'clock, 1 at 5 o'clock, measured clockwise from "up".
  double _angle(double v) => (-135 + 270 * ((v - min) / (max - min)).clamp(0.0, 1.0)) * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ringR = r - 3;
    final body = r * 0.80;
    const start = -math.pi / 2; // canvas angle 0 is 3 o'clock, so "up" is -90 degrees

    // the faint track
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withAlpha(22);
    canvas.drawArc(Rect.fromCircle(center: c, radius: ringR), start + _angle(min), 270 * math.pi / 180, false, track);

    // the value, drawn from the resting point (the middle for balance, the start for the others)
    final from = _angle(reset);
    final to = _angle(value);
    if ((to - from).abs() > 0.003) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final rect = Rect.fromCircle(center: c, radius: ringR);
      if (hotFrom != null && value > hotFrom!) {
        final hotA = _angle(hotFrom!);
        canvas.drawArc(rect, start + from, hotA - from, false, p..color = accent);
        canvas.drawArc(rect, start + hotA, to - hotA, false, p..color = const Color(0xFFFF2D2D));
      } else {
        canvas.drawArc(rect, start + math.min(from, to), (to - from).abs(), false, p..color = accent);
      }
    }

    // the body
    canvas.drawCircle(c + const Offset(0, 3), body, Paint()..color = Colors.black.withAlpha(90)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(c, body, Paint()..color = const Color(0xFF222227));
    canvas.drawCircle(c, body, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withAlpha(46));

    // the notch
    final a = _angle(value);
    final dir = Offset(math.sin(a), -math.cos(a));
    final p1 = c + dir * (body * 0.62);
    final p2 = c + dir * (body * 0.86);
    canvas.drawLine(p1, p2, Paint()
      ..strokeWidth = size.width > 140 ? 6 : 5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withAlpha(215));
  }

  @override
  bool shouldRepaint(_KnobPainter o) => o.value != value || o.accent != accent || o.hotFrom != hotFrom;
}

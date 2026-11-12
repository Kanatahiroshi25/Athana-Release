import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// The look of the Athana web app, in Flutter: near-black with two soft glows, glass cards,
// gradient headline, pill buttons, coloured tiles.

const Color kBg = Color(0xFF07060C);
const Color kPanel = Color(0xFF1B1A20);
const Color kSheet = Color(0xFF1D1D20);

/// The lighter partner of the accent colour (used for highlights and the active tab).
Color lighter(Color a) => Color.lerp(a, Colors.white, 0.42)!;
Color darker(Color a, double t) => Color.lerp(a, Colors.black, t)!;

BoxDecoration glass({double radius = 20}) => BoxDecoration(
      color: const Color(0xB8181520),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withAlpha(26)),
    );

BoxDecoration darkPill() => BoxDecoration(
      color: Colors.black.withAlpha(140),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withAlpha(26)),
    );

/// How the background looks (Settings → Appearance and Performance). The page backgrounds listen to it.
class Look {
  final String bg; // 'ambient', 'aurora' or 'minimal'
  final double glow; // 0..1
  final String? wall; // path of the wallpaper picture, if any
  final double wallBlur; // 0..40
  final double wallDim; // 0..0.9
  final bool lite; // Performance mode: no live blur, no moving glow
  final bool calm; // Reduce animations
  const Look({this.bg = 'ambient', this.glow = 1, this.wall, this.wallBlur = 0, this.wallDim = 0.35, this.lite = false, this.calm = false});

  @override
  bool operator ==(Object o) =>
      o is Look && o.bg == bg && o.glow == glow && o.wall == wall && o.wallBlur == wallBlur && o.wallDim == wallDim && o.lite == lite && o.calm == calm;

  @override
  int get hashCode => Object.hash(bg, glow, wall, wallBlur, wallDim, lite, calm);
}

final ValueNotifier<Look> kLook = ValueNotifier<Look>(const Look());

/// Page background: black, a dotted grid and soft glows in the accent colour, or your own wallpaper.
class Backdrop extends StatelessWidget {
  final Color accent;
  final Widget child;
  const Backdrop({super.key, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Look>(
      valueListenable: kLook,
      builder: (BuildContext context, Look look, Widget? _) {
        final g = look.glow;
        final wall = look.wall;
        return Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: kBg),
          if (wall != null) ...[
            Positioned.fill(child: RepaintBoundary(child: WallImage(path: wall, blur: look.wallBlur))),
            Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.black.withAlpha((look.wallDim * 255).round())))),
          ] else if (look.bg == 'aurora')
            Positioned.fill(child: _Aurora(accent: accent, glow: g, animate: !look.calm && !look.lite))
          else if (look.bg == 'ambient') ...[
            Positioned(left: -150, top: -190, child: RepaintBoundary(child: _Glow(color: accent, alpha: (105 * g).round()))),
            Positioned(right: -170, bottom: -210, child: RepaintBoundary(child: _Glow(color: lighter(accent), alpha: (76 * g).round()))),
          ],
          if (wall == null && look.bg != 'minimal') const Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _Dots())))),
          // A transparent Material so that taps and highlights inside draw above the background.
          Material(type: MaterialType.transparency, child: child),
        ]);
      },
    );
  }
}

/// The wallpaper picture, covering the whole screen, with optional blur.
class WallImage extends StatelessWidget {
  final String path;
  final double blur;
  const WallImage({super.key, required this.path, required this.blur});

  @override
  Widget build(BuildContext context) {
    // A blurred picture needs no detail, so it is decoded smaller.
    Widget img = Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: blur > 0 ? 720 : 1440,
      gaplessPlayback: true,
      errorBuilder: (BuildContext c, Object e, StackTrace? s) => const SizedBox.shrink(),
    );
    if (blur > 0) {
      img = ClipRect(child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.mirror), child: img));
    }
    return SizedBox.expand(child: img);
  }
}

/// Three big glows that drift slowly (Aurora background).
class _Aurora extends StatefulWidget {
  final Color accent;
  final double glow;
  final bool animate;
  const _Aurora({required this.accent, required this.glow, required this.animate});

  @override
  State<_Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<_Aurora> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 28));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(_Aurora old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.accent;
    final hsl = HSLColor.fromColor(a);
    final third = hsl.withHue((hsl.hue + 70) % 360).toColor();
    final g = widget.glow;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? _) {
          final t = _c.value * 2 * math.pi;
          return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
            final w = box.maxWidth, h = box.maxHeight;
            Widget blob(Color c, int alpha, double fx, double fy, double px, double py) => Positioned(
                  left: w * fx + math.sin(t + px) * w * 0.18 - 280,
                  top: h * fy + math.cos(t * 0.8 + py) * h * 0.12 - 280,
                  child: _Glow(color: c, alpha: (alpha * g).round()),
                );
            return Stack(children: [
              blob(a, 120, 0.15, 0.12, 0, 0),
              blob(lighter(a), 90, 0.9, 0.55, 2, 1.5),
              blob(third, 80, 0.4, 0.95, 4, 3),
            ]);
          });
        },
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final int alpha;
  const _Glow({required this.color, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 560,
        height: 560,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withAlpha(alpha), color.withAlpha(0)]),
        ),
      ),
    );
  }
}

class _Dots extends CustomPainter {
  const _Dots();
  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    for (double y = 0; y < size.height; y += 24) {
      for (double x = 0; x < size.width; x += 24) {
        pts.add(Offset(x + 12, y + 12));
      }
    }
    final paint = Paint()
      ..color = Colors.white.withAlpha(18)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(ui.PointMode.points, pts, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Big headline text filled with a white-to-accent gradient that slowly slides back and forth.
class GradText extends StatefulWidget {
  final String text;
  final Color accent;
  final double size;
  const GradText(this.text, {super.key, required this.accent, this.size = 40});

  @override
  State<GradText> createState() => _GradTextState();
}

class _GradTextState extends State<GradText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void initState() {
    super.initState();
    if (!kLook.value.calm) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? _) {
        final t = Curves.easeInOut.transform(_c.value);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect r) => LinearGradient(
            begin: Alignment(-1 - 2 * t, 0),
            end: Alignment(3 - 2 * t, 0),
            colors: [Colors.white, lighter(accent), accent],
            stops: const [0.08, 0.52, 1.0],
          ).createShader(r),
          child: Text(widget.text, style: TextStyle(fontSize: widget.size, fontWeight: FontWeight.w900, letterSpacing: -1, height: 1.1, color: Colors.white)),
        );
      },
    );
  }
}

/// Fades and slides its child in, a little later for each index (the Library tiles do this).
class Reveal extends StatefulWidget {
  final int index;
  final Widget child;
  const Reveal({super.key, required this.index, required this.child});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (kLook.value.calm) {
      _c.value = 1;
      return;
    }
    _t = Timer(Duration(milliseconds: 45 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (BuildContext context, Widget? w) => Transform.translate(offset: Offset(0, 16 * (1 - _curve.value)), child: w),
        child: widget.child,
      ),
    );
  }
}

/// Small rounded label with an optional icon ("3 songs", "1 min").
class InfoChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool highlight;
  const InfoChip({super.key, this.icon, required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? const Color(0xFF2A1700) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: highlight ? const LinearGradient(colors: [Color(0xFFF6D365), Color(0xFFFDA085)]) : null,
        color: highlight ? null : Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: highlight ? null : Border.all(color: Colors.white.withAlpha(26)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 6)],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

/// The round-ended action button: filled with the accent gradient, or "ghost" (glassy).
class Cta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color accent;
  final bool ghost, compact;
  const Cta({super.key, required this.label, required this.icon, required this.onTap, required this.accent, this.ghost = false, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final fg = ghost ? Colors.white : const Color(0xFF0B0B10);
    final radius = BorderRadius.circular(999);
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: ghost ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(accent), accent]),
            color: ghost ? Colors.white.withAlpha(23) : null,
            border: ghost ? Border.all(color: Colors.white.withAlpha(41)) : null,
            boxShadow: ghost ? null : [BoxShadow(color: accent.withAlpha(150), blurRadius: 30, offset: const Offset(0, 10), spreadRadius: -8)],
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 22, vertical: compact ? 10 : 13),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: compact ? 16 : 17, color: fg),
                const SizedBox(width: 9),
                Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 13 : 14, color: fg)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// One option in a row of choices (like "5 s  10 s  15 s").
class PillChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const PillChoice({super.key, required this.label, required this.selected, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(90) : Colors.white.withAlpha(20),
          borderRadius: radius,
          border: Border.all(color: selected ? lighter(accent).withAlpha(150) : Colors.white.withAlpha(20)),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.white.withAlpha(200))),
          ),
        ),
      ),
    );
  }
}

/// Little dancing bars (shown next to the song that is playing).
class EqBars extends StatefulWidget {
  final bool playing;
  final Color color;
  final double height;
  final int count;
  const EqBars({super.key, required this.playing, required this.color, this.height = 20, this.count = 4});

  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(EqBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? _) {
        return SizedBox(
          height: widget.height,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < widget.count; i++)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Container(
                  width: 3,
                  height: widget.height * (0.2 + 0.8 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi * (1 + (i % 3) * 0.5) + i * 1.3))),
                  decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
                ),
              ),
          ]),
        );
      },
    );
  }
}

/// A placeholder wave shape for the seek bar. It is made from the song title, so it is the same
/// every time, and it is not a measurement of the audio (the web version does the same).
List<double> pseudoPeaks(String seed) {
  var h = 7;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  final out = <double>[];
  for (var i = 0; i < 256; i++) {
    h = (h * 1664525 + 1013904223) & 0xFFFFFFFF;
    final r = h / 4294967296;
    out.add(0.2 + 0.8 * math.sin(i / 8 + r * 2).abs() * (0.45 + 0.55 * r));
  }
  return out;
}

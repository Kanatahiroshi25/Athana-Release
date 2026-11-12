import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../design.dart';
import '../models.dart';
import '../widgets.dart';
import '../edit_dialog.dart';
import '../hires.dart';
import 'analysis_screen.dart';
import 'eq_screen.dart';
import 'lyrics_view.dart';
import 'online_find.dart';
import 'queue_screen.dart';
import 'signal_path.dart';

class NowPlayingScreen extends StatefulWidget {
  final AppState state;
  const NowPlayingScreen({super.key, required this.state});
  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  String _peakKey = '';
  List<double> _peaks = const <double>[];
  bool _lyrOpen = false; // the lyrics take the place of the cover
  int _rtab = 0; // landscape: the right side shows 0 = Up Next, 1 = Lyrics
  AppState get s => widget.state;

  List<double> _peaksFor(Track t) {
    if (_peakKey != t.key) {
      _peakKey = t.key;
      _peaks = pseudoPeaks(t.title);
    }
    return _peaks;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (BuildContext context, Widget? _) {
        final t = s.current;
        final accent = accentOf(s);
        if (t == null) {
          return Column(children: [
            _topBar(accent),
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.headphones_rounded, size: 72, color: Colors.white.withAlpha(50)),
                  const SizedBox(height: 12),
                  Text('Nothing playing', style: TextStyle(fontSize: 18, color: Colors.white.withAlpha(150))),
                ]),
              ),
            ),
          ]);
        }
        if (_isLand) return _landscape(context, t, accent);
        final art = coverFile(t.art);
        return Stack(fit: StackFit.expand, children: [
          if (art != null && !kLook.value.lite && kLook.value.wall == null && kLook.value.bg != 'minimal')
            Positioned.fill(
              child: RepaintBoundary(
                child: Opacity(
                  opacity: 0.4,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Image(image: ResizeImage(FileImage(art), width: 160), fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
            final focus = s.prefs.focus;
            final cw = math.max(0.0, box.maxWidth - 32).toDouble();
            final coverH = focus
                ? math.min(cw, math.max(170.0, box.maxHeight - 56 - 176 - 40)).toDouble()
                : math.min(cw, math.max(170.0, box.maxHeight - 56 - 52 - 176 - 40 - 60 - (s.hrState.isNotEmpty ? 74.0 : 0.0))).toDouble();
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(children: [
                  focus ? _focusBar() : _topBar(accent),
                  _lyrOpen
                      ? Container(
                    width: cw,
                    height: coverH,
                    decoration: glass(radius: 28),
                    clipBehavior: Clip.antiAlias,
                    child: LyricsView(state: s, accent: accent),
                  )
                      : _cover(t, accent, cw, coverH),
                  const SizedBox(height: 12),
                  if (!focus) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _pillRow(context, accent)),
                  if (!focus) const SizedBox(height: 6),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _WaveDeck(state: s, peaks: _peaksFor(t), accent: accent)),

                  // Sleek Audio Quality Pill
                  if (!focus)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildQualityIndicator(accent),
                    ),

                  if (s.prepping) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Getting this song from Google Drive…', style: TextStyle(color: Colors.white.withAlpha(170)))),
                  if (s.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.error!, style: const TextStyle(color: Color(0xFFFF8A80)))),
                  const SizedBox(height: 64),
                ]),
              ),
            );
          }),
          if (!s.prefs.focus) Positioned(left: 0, right: 0, bottom: 0, child: _strip(context, accent)),
        ]);
      },
    );
  }

  Widget _buildQualityIndicator(Color accent) {
    final t = s.current;
    if (t == null || s.format.isEmpty) return const SizedBox.shrink();

    final bits = s.hrState == 'done' && s.hrResult != null ? ((s.hrResult!['bits'] ?? 0) as int) : t.bits;
    final fileRate = s.infoRate > 0 ? s.infoRate : t.rate;
    final dur = s.durationMs > 0 ? s.durationMs : t.durationMs;
    final kbps = (t.size > 0 && dur > 0) ? (t.size * 8 / (dur / 1000) / 1000).round() : 0;

    const lossless = {'wav', 'wave', 'aif', 'aiff', 'flac'};
    const lossy = {'mp3', 'ogg', 'oga', 'opus', 'aac'};
    final bool? isLossless = lossless.contains(t.ext) ? true : (lossy.contains(t.ext) ? false : null);
    final bool isHiRes = isLossless == true && (bits >= 24 || fileRate > 48000);
    final bool isCD = isLossless == true && bits == 16 && fileRate == 44100;

    String label = '';
    if (isLossless == true) {
      if (isHiRes) {
        label = 'HI-RES';
      } else if (isCD) {
        label = 'CD QUALITY';
      } else {
        label = 'LOSSLESS';
      }
    } else if (isLossless == false) {
      label = 'LOSSY';
    }

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => AnalysisScreen(state: s))),
      onLongPress: () => showSignalPath(context, s),
      child: AudioQualityIndicator(
        format: t.isAiff ? 'AIFF' : (t.ext == 'wave' ? 'WAV' : t.ext.toUpperCase()),
        fileRate: fileRate,
        directRate: s.infoOut,
        bits: bits,
        kbps: kbps,
        label: label,
        isHiRes: isHiRes,
        scanState: s.hrState,
        accentColor: accent,
      ),
    );
  }

  // ---------------------------------------------------------------- landscape
  bool get _isLand {
    final mq = MediaQuery.of(context);
    return mq.orientation == Orientation.landscape && mq.size.width >= 560;
  }

  void _toggleLyrics() {
    if (_isLand) {
      setState(() => _rtab = _rtab == 1 ? 0 : 1);
    } else {
      setState(() => _lyrOpen = !_lyrOpen);
    }
  }

  Widget _landscape(BuildContext context, Track t, Color accent) {
    final art = coverFile(t.art);
    final focus = s.prefs.focus;
    return Stack(fit: StackFit.expand, children: [
      if (art != null && !kLook.value.lite && kLook.value.wall == null && kLook.value.bg != 'minimal')
        Positioned.fill(
          child: RepaintBoundary(
            child: Opacity(
              opacity: 0.4,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Image(image: ResizeImage(FileImage(art), width: 160), fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
        final h = box.maxHeight;
        final leftW = focus ? box.maxWidth : math.min(box.maxWidth * 0.6, math.max(box.maxWidth * 0.46, 332.0)).toDouble();
        final r = h - (focus ? 24.0 : 24.0 + 36 + 6 + 30 + 6 + 80.0);
        final deckH = (r * 0.42).clamp(96.0, 150.0).toDouble();
        final side = math.max(80.0, math.min(leftW - 24, r - deckH - 8)).toDouble();
        final left = SizedBox(
          width: leftW,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: h),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(height: 8),
                _cover(t, accent, side, side),
                const SizedBox(height: 8),
                if (!focus)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: LayoutBuilder(
                      builder: (BuildContext c, BoxConstraints bc) => FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(width: math.max(328.0, bc.maxWidth), child: _pillRow(context, accent)),
                      ),
                    ),
                  ),
                if (!focus) const SizedBox(height: 6),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _WaveDeck(state: s, peaks: _peaksFor(t), accent: accent, height: deckH)),

                if (!focus) Padding(padding: const EdgeInsets.only(top: 8), child: _buildQualityIndicator(accent)),

                if (s.prepping) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Getting this song from Google Drive…', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(170)))),
                if (s.error != null) Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 0), child: Text(s.error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFFFF8A80)))),
                const SizedBox(height: 8),
              ]),
            ),
          ),
        );
        if (focus) {
          return Stack(children: [
            Center(child: left),
            Positioned(top: 8, right: 12, child: _RoundBtn(icon: Icons.fullscreen_exit_rounded, tooltip: 'Leave focus mode', onTap: () { s.prefs.focus = false; s.savePrefs(); })),
          ]);
        }
        return Row(children: [
          left,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
              child: Column(children: [
                Row(children: [
                  GestureDetector(onTap: () => setState(() => _rtab = 0), child: _StripTab(label: 'Up Next', active: _rtab == 0, accent: accent)),
                  const SizedBox(width: 22),
                  GestureDetector(onTap: () => setState(() => _rtab = 1), child: _StripTab(label: 'Lyrics', active: _rtab == 1, accent: accent)),
                  const SizedBox(width: 22),
                  GestureDetector(onTap: () => kTab.value = 0, child: const _StripTab(label: 'Library', active: false, accent: Colors.white)),
                  const Spacer(),
                  Text('ATHANA  MELODY', style: TextStyle(fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(110))),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: darkPill(),
                    child: const Text('v$kVersion', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ]),
                Expanded(
                  child: _rtab == 0
                      ? QueueScreen(state: s)
                      : Container(
                    margin: const EdgeInsets.only(top: 6, bottom: 8),
                    decoration: glass(radius: 24),
                    clipBehavior: Clip.antiAlias,
                    child: LyricsView(state: s, accent: accent),
                  ),
                ),
              ]),
            ),
          ),
        ]);
      }),
    ]);
  }

  // ---------------------------------------------------------------- top bar
  Widget _focusBar() {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          _RoundBtn(icon: Icons.fullscreen_exit_rounded, tooltip: 'Leave focus mode', onTap: () { s.prefs.focus = false; s.savePrefs(); }),
        ]),
      ),
    );
  }

  Widget _topBar(Color accent) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          _RoundBtn(icon: Icons.apps_rounded, tooltip: 'Library', onTap: () => kTab.value = 0),
          const SizedBox(width: 12),
          Expanded(
            child: Row(children: [
              Expanded(child: Container(height: 1, color: Colors.white.withAlpha(30))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('ATHANA  MELODY', style: TextStyle(fontSize: 11, letterSpacing: 3.6, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(128))),
              ),
              Expanded(child: Container(height: 1, color: Colors.white.withAlpha(30))),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: darkPill(),
            child: const Text('v$kVersion', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- cover
  void _coverAction(String a) {
    tapFeedback(s);
    switch (a) {
      case 'playpause': s.togglePlay();
      case 'next': s.next();
      case 'prev': s.prev();
      case 'more': if (s.current != null) _moreSheet(accentOf(s));
      case 'signal': showSignalPath(context, s);
      case 'lyrics': _toggleLyrics();
    }
  }

  Widget _cover(Track t, Color accent, double w, double h) {
    final bits = s.hrState == 'done' && s.hrResult != null ? ((s.hrResult!['bits'] ?? 0) as int) : t.bits;
    final rate = s.infoRate > 0 ? s.infoRate : t.rate;
    final isLossless = const {'wav', 'wave', 'aif', 'aiff', 'flac'}.contains(t.ext);
    final isHiRes = isLossless && (bits >= 24 || rate > 48000);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (DragEndDetails d) {
        if (!s.prefs.swipe) return;
        final v = (d.primaryVelocity ?? 0) * (s.prefs.swipeRev ? -1 : 1);
        if (v < -300) {
          tapFeedback(s);
          s.next();
        } else if (v > 300) {
          tapFeedback(s);
          s.prev();
        }
      },
      onDoubleTap: s.prefs.dblTap == 'off' ? null : () => _coverAction(s.prefs.dblTap),
      onLongPress: s.prefs.lpress == 'off' ? null : () => _coverAction(s.prefs.lpress),
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withAlpha(26)),
          boxShadow: [BoxShadow(color: accent.withAlpha(70), blurRadius: 40, spreadRadius: -4)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          if (coverFile(t.art) != null)
            Positioned.fill(child: Cover(path: t.art, size: w, height: h, radius: 0))
          else
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1F1C2C), Color(0xFF928DAB)])),
                child: Icon(Icons.music_note_rounded, size: 84, color: Colors.white.withAlpha(60)),
              ),
            ),

          // 👇 FLAWLESS NATIVE HI-RES BADGE 👇
          if (isHiRes && w >= 200)
            const Positioned(
              top: 12,
              right: 12,
              child: HiResLogo(width: 48),
            ),
          // 👆 -------------------------------- 👆

          Positioned(
            left: 12,
            right: w < 230 ? 12 : 64,
            bottom: 12,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: darkPill(),
                child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: darkPill(),
                child: Text(t.artist.isNotEmpty ? t.artist : t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(204))),
              ),
            ]),
          ),
          if (w < 230)
            Positioned(right: 8, top: 8, child: _RoundBtn(icon: Icons.more_vert_rounded, tooltip: 'More', onTap: () => _moreSheet(accent)))
          else
            Positioned(right: 12, bottom: 12, child: _RoundBtn(icon: Icons.more_vert_rounded, tooltip: 'More', onTap: () => _moreSheet(accent))),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- strip
  Widget _strip(BuildContext context, Color accent) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _queueSheet,
      onVerticalDragEnd: (DragEndDetails d) {
        if ((d.primaryVelocity ?? 0) < -150) _queueSheet();
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xEB0D0C14),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white.withAlpha(26))),
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white.withAlpha(64), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 6),
          Row(children: [
            _StripTab(label: 'Up Next', active: true, accent: accent),
            const SizedBox(width: 22),
            GestureDetector(onTap: () => kTab.value = 0, child: const _StripTab(label: 'Library', active: false, accent: Colors.white)),
            const Spacer(),
            IconButton(tooltip: 'Open the queue', icon: Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white.withAlpha(180)), onPressed: _queueSheet),
          ]),
        ]),
      ),
    );
  }

  void _queueSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (BuildContext c) => SizedBox(
        height: MediaQuery.of(c).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white.withAlpha(64), borderRadius: BorderRadius.circular(2))),
          ),
          Expanded(child: QueueScreen(state: s)),
        ]),
      ),
    );
  }

  void _moreSheet(Color accent) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit title / artist', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.of(c).pop();
              final t = s.current;
              if (t != null) showEditDialog(context, s, track: t);
            },
          ),
          ListTile(
            leading: const Icon(Icons.graphic_eq_rounded),
            title: const Text('Analyse song', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Spectrogram and true hi-res check'),
            onTap: () {
              Navigator.of(c).pop();
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => AnalysisScreen(state: s)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.travel_explore_rounded),
            title: const Text('Find cover and tags online', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('MusicBrainz and the Cover Art Archive'),
            onTap: () {
              Navigator.of(c).pop();
              final t = s.current;
              if (t != null) showOnlineFind(context, s, t);
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Change cover', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Pick a picture from your phone'),
            onTap: () async {
              Navigator.of(c).pop();
              final t = s.current;
              if (t == null) return;
              final msg = await s.changeCover([t]);
              if (msg != null && mounted) toast(context, msg);
            },
          ),
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: const Text('Playback speed', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${s.speed}×'),
            onTap: () {
              Navigator.of(c).pop();
              _speedSheet(context, accent);
            },
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Sleep timer', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(s.stopAfter ? 'End of song' : (s.sleepMinutes > 0 ? '${s.sleepMinutes} min' : 'Off')),
            onTap: () {
              Navigator.of(c).pop();
              _sleepSheet(context, accent);
            },
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- pills
  Widget _pillRow(BuildContext context, Color accent) {
    final on = lighter(accent);
    final off = Colors.white.withAlpha(150);
    final sleepOn = s.sleepMinutes > 0 || s.stopAfter;
    return Row(children: [
      _CtlPill(
        icon: Icons.schedule_rounded,
        label: s.stopAfter ? 'end' : (s.sleepMinutes > 0 ? '${s.sleepMinutes}m' : ''),
        color: sleepOn ? on : off,
        onTap: () => _sleepSheet(context, accent),
      ),
      const SizedBox(width: 6),
      _CtlPill(icon: Icons.speed_rounded, label: '${s.speed}×', color: s.speed == 1.0 ? off : on, onTap: () => _speedSheet(context, accent)),
      const SizedBox(width: 6),
      _CtlPill(
        icon: Icons.sync_alt_rounded,
        label: s.loopB >= 0 ? 'A–B' : (s.loopA >= 0 ? 'A' : ''),
        color: s.loopA >= 0 ? on : off,
        onTap: () {
          tapFeedback(s);
          toast(context, s.loopStep());
        },
      ),
      const SizedBox(width: 6),
      _CtlPill(
        icon: Icons.equalizer_rounded,
        label: s.prefs.eqOn ? 'EQ' : '',
        color: s.prefs.eqOn ? on : off,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => EqScreen(state: s))),
      ),
      const Spacer(),
      _CtlPill(icon: Icons.lyrics_rounded, label: '', color: (_isLand ? _rtab == 1 : _lyrOpen) ? on : off, onTap: _toggleLyrics),
      const SizedBox(width: 6),
      _CtlPill(icon: s.repeat == 2 ? Icons.repeat_one_rounded : Icons.repeat_rounded, label: '', color: s.repeat == 0 ? off : on, onTap: () { tapFeedback(s); s.cycleRepeat(); }),
      const SizedBox(width: 6),
      _CtlPill(icon: Icons.shuffle_rounded, label: '', color: s.shuffle ? on : off, onTap: () { tapFeedback(s); s.toggleShuffle(); }),
    ]);
  }

  void _speedSheet(BuildContext context, Color accent) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Playback speed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                PillChoice(label: '$r×', selected: s.speed == r, accent: accent, onTap: () { s.setSpeed(r); Navigator.of(c).pop(); }),
            ]),
          ]),
        ),
      ),
    );
  }

  void _sleepSheet(BuildContext context, Color accent) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sleep timer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(s.prefs.sleepFinish ? 'The current song finishes first.' : 'Playback stops when the time is up.', style: TextStyle(color: Colors.white.withAlpha(130))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [0, 15, 30, 45, 60, 90])
                PillChoice(label: m == 0 ? 'Off' : '$m min', selected: s.sleepMinutes == m && !s.stopAfter, accent: accent, onTap: () { s.setSleep(m); Navigator.of(c).pop(); }),
            ]),
          ]),
        ),
      ),
    );
  }
}

// 👇 AUDIO QUALITY INDICATOR WIDGET 👇
class AudioQualityIndicator extends StatelessWidget {
  final String format;
  final int fileRate;
  final int directRate;
  final int bits;
  final int kbps;
  final String label;
  final bool isHiRes;
  final String scanState;
  final Color accentColor;

  const AudioQualityIndicator({
    super.key,
    required this.format,
    required this.fileRate,
    required this.directRate,
    required this.bits,
    required this.kbps,
    required this.label,
    required this.isHiRes,
    required this.scanState,
    required this.accentColor,
  });

  String _fmtRate(int rate) => rate > 0 ? '${(rate / 1000).toStringAsFixed(1).replaceAll('.0', '')} kHz' : '--';

  @override
  Widget build(BuildContext context) {
    Widget badge = const SizedBox.shrink();
    if (isHiRes) {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF6D365), Color(0xFFFDA085)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(color: const Color(0xFFF6D365).withAlpha(80), blurRadius: 8, spreadRadius: 1),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF2A1700), letterSpacing: 1.0),
        ),
      );
    } else if (label.isNotEmpty) {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: label == 'LOSSY' ? Colors.white.withAlpha(26) : accentColor.withAlpha(77),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: label == 'LOSSY' ? Colors.transparent : accentColor.withAlpha(153)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: label == 'LOSSY' ? Colors.white.withAlpha(153) : Colors.white, letterSpacing: 1.0),
        ),
      );
    }

    Widget infoRow = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        if (format.isNotEmpty) Text(format, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accentColor)),
        if (format.isNotEmpty && bits > 0) Text('·', style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(128))),
        if (bits > 0) Text('${bits}-bit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(230))),
        if (bits > 0 && fileRate > 0) Text('·', style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(128))),
        if (fileRate > 0) Text(_fmtRate(fileRate), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(230))),
        if (kbps > 0) Text('·', style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(128))),
        if (kbps > 0) Text('~$kbps KBPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(230))),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 4),
          badge,
        ],
      ],
    );

    Widget subRow = const SizedBox.shrink();
    if (scanState == 'analysing' || scanState == 'wait') {
      subRow = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: accentColor)),
          const SizedBox(width: 6),
          Text('Checking lossless quality...', style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(128), fontWeight: FontWeight.w500)),
        ],
      );
    } else if (scanState == 'done' && directRate > 0) {
      final isDirect = directRate == fileRate;
      subRow = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.surround_sound, size: 12, color: isDirect ? Colors.greenAccent : Colors.orangeAccent),
          const SizedBox(width: 4),
          Text(
            isDirect ? 'Direct: ${_fmtRate(directRate)} (Bit-perfect)' : 'Resampled to ${_fmtRate(directRate)}',
            style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(153), fontWeight: FontWeight.w600),
          ),
        ],
      );
    } else if (scanState == 'failed') {
      subRow = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 12, color: Color(0xFFFF8A80)),
          const SizedBox(width: 4),
          Text('Could not verify quality', style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(128), fontWeight: FontWeight.w500)),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withAlpha(26), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              infoRow,
              if (subRow is! SizedBox) ...[
                const SizedBox(height: 6),
                subRow,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Hi-Res Audio logo (official SVG, see assets/icons/hires_audio.svg)
class HiResLogo extends StatelessWidget {
  final double width;
  const HiResLogo({super.key, this.width = 44});

  @override
  Widget build(BuildContext context) {
    // The logo is square (1:1), so height == width.
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SvgPicture.asset(
        'assets/icons/hires_audio.svg',
        width: width,
        height: width,
        semanticsLabel: 'Hi-Res Audio',
      ),
    );
  }
}

class _StripTab extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  const _StripTab({required this.label, required this.active, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: IntrinsicWidth(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.white.withAlpha(115))),
          const SizedBox(height: 4),
          Container(height: 2, decoration: BoxDecoration(color: active ? lighter(accent) : Colors.transparent, borderRadius: BorderRadius.circular(2), boxShadow: active ? [BoxShadow(color: accent, blurRadius: 8)] : null)),
        ]),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Ink(
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withAlpha(110), border: Border.all(color: Colors.white.withAlpha(26))),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 18, color: Colors.white.withAlpha(204)))),
        ),
      ),
    );
  }
}

class _CtlPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _CtlPill({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(color: Colors.black.withAlpha(90), borderRadius: radius, border: Border.all(color: Colors.white.withAlpha(20))),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: color),
              if (label.isNotEmpty) ...[const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))],
            ]),
          ),
        ),
      ),
    );
  }
}

class _WaveDeck extends StatefulWidget {
  final AppState state;
  final List<double> peaks;
  final Color accent;
  final double height;
  const _WaveDeck({required this.state, required this.peaks, required this.accent, this.height = 176});
  @override
  State<_WaveDeck> createState() => _WaveDeckState();
}

class _WaveDeckState extends State<_WaveDeck> with SingleTickerProviderStateMixin {
  static const double _loop = 6.981317;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(microseconds: 6981317));
  double? drag;
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (s.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!s.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    s.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  double _frac(Offset p, double w) => (p.dx / w).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final p = s.prefs;
    return ValueListenableBuilder<int>(
      valueListenable: s.positionMs,
      builder: (BuildContext context, int pos, Widget? _) {
        final dur = s.durationMs;
        final prog = (drag ?? (dur > 0 ? pos / dur : 0.0)).clamp(0.0, 1.0).toDouble();
        final shown = (prog * dur).round();
        return SizedBox(
          height: widget.height,
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
            final w = box.maxWidth;
            return Stack(children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: dur > 0 ? (TapUpDetails d) => s.seekTo((_frac(d.localPosition, w) * dur).round()) : null,
                  onHorizontalDragStart: dur > 0 ? (DragStartDetails d) => setState(() => drag = _frac(d.localPosition, w)) : null,
                  onHorizontalDragUpdate: dur > 0 ? (DragUpdateDetails d) => setState(() => drag = _frac(d.localPosition, w)) : null,
                  onHorizontalDragEnd: (DragEndDetails d) {
                    final f = drag;
                    setState(() => drag = null);
                    if (f != null && dur > 0) s.seekTo((f * dur).round());
                  },
                  onHorizontalDragCancel: () => setState(() => drag = null),
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (BuildContext context, Widget? _) => CustomPaint(painter: _BarsPainter(widget.peaks, prog, widget.accent, s.playing, _c.value * _loop, loopA: dur > 0 && s.loopA >= 0 ? s.loopA / dur : -1, loopB: dur > 0 && s.loopB >= 0 ? s.loopB / dur : -1), size: Size.infinite),
                  ),
                ),
              ),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _Circ(size: 38, icon: Icons.keyboard_double_arrow_left_rounded, iconSize: 16, dim: true, tooltip: 'Previous', onTap: () { tapFeedback(s); s.prev(); }),
                  const SizedBox(width: 8),
                  _Circ(size: 56, icon: Icons.fast_rewind_rounded, iconSize: 24, tooltip: 'Back ${p.skipSec} s', onTap: () { tapFeedback(s); s.skip(-p.skipSec); }),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _c,
                    builder: (BuildContext context, Widget? _) => _Circ(
                      size: 80,
                      icon: s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      iconSize: 40,
                      ring: lighter(widget.accent),
                      glow: widget.accent,
                      glowBlur: s.playing ? 20 + 14 * (0.5 + 0.5 * math.sin(_c.value * _loop * 4.5)) : 24,
                      tooltip: s.playing ? 'Pause' : 'Play',
                      onTap: () { tapFeedback(s); s.togglePlay(); },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Circ(size: 56, icon: Icons.fast_forward_rounded, iconSize: 24, tooltip: 'Forward ${p.skipSec} s', onTap: () { tapFeedback(s); s.skip(p.skipSec); }),
                  const SizedBox(width: 8),
                  _Circ(size: 38, icon: Icons.keyboard_double_arrow_right_rounded, iconSize: 16, dim: true, tooltip: 'Next', onTap: () { tapFeedback(s); s.next(); }),
                ]),
              ),
              Positioned(left: 4, bottom: 0, child: _TimePill(fmtTime(shown))),
              Positioned(
                right: 4,
                bottom: 0,
                child: GestureDetector(
                  onTap: () { p.remain = !p.remain; s.savePrefs(); },
                  child: _TimePill(p.remain ? '-${fmtTime(dur - shown)}' : fmtTime(dur)),
                ),
              ),
            ]);
          }),
        );
      },
    );
  }
}

class _TimePill extends StatelessWidget {
  final String text;
  const _TimePill(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: darkPill(),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
  );
}

class _Circ extends StatelessWidget {
  final double size, iconSize;
  final IconData icon;
  final bool dim;
  final Color? ring, glow;
  final double? glowBlur;
  final String tooltip;
  final VoidCallback onTap;
  const _Circ({required this.size, required this.icon, required this.iconSize, required this.tooltip, required this.onTap, this.dim = false, this.ring, this.glow, this.glowBlur});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Ink(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withAlpha(dim ? 64 : 160),
            border: Border.all(color: ring ?? Colors.white.withAlpha(36), width: ring != null ? 2 : 1),
            boxShadow: [BoxShadow(color: (glow ?? Colors.black).withAlpha(glow != null ? 110 : 100), blurRadius: glowBlur ?? (glow != null ? 26 : 14))],
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Icon(icon, size: iconSize, color: Colors.white.withAlpha(dim ? 150 : 255))),
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<double> peaks;
  final double prog;
  final Color accent;
  final bool playing;
  final double tm;
  final double loopA, loopB;

  const _BarsPainter(this.peaks, this.prog, this.accent, this.playing, this.tm,
      {this.loopA = -1, this.loopB = -1});

  @override
  void paint(Canvas canvas, Size size) {
    const bw = 5.0,
        gap = 4.0;
    final w = size.width,
        h = size.height;
    if (w <= 0 || h <= 0 || peaks.isEmpty) return;
    final n = math.max(1, ((w + gap) / (bw + gap)).floor());
    final played = Paint()
      ..color = accent.withAlpha(242);
    final glow = Paint()
      ..color = accent.withAlpha(110)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final rest = Paint()
      ..color = Colors.white.withAlpha(179);
    for (var i = 0; i < n; i++) {
      final a = (i / n * peaks.length).floor();
      final b = math.max(a + 1, ((i + 1) / n * peaks.length).floor());
      var v = 0.0;
      for (var k = a; k < b && k < peaks.length; k++) {
        v = math.max(v, peaks[k]);
      }
      v = math.max(0.06, v);
      final dist = ((i + 0.5) - prog * n).abs();
      final bounce = playing && dist < 7 ? 1 +
          0.2 * math.sin(tm * 9 - i * 0.7) * (1 - dist / 7) : 1.0;
      final bh = math.min(h, math.max(6.0, v * h * 0.9) * bounce);
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (bw + gap), (h - bh) / 2, bw, bh),
          const Radius.circular(2));
      final done = (i + 0.5) / n <= prog;
      if (done) canvas.drawRRect(r, glow);
      canvas.drawRRect(r, done ? played : rest);
    }
    if (loopA >= 0) {
      final ax = loopA.clamp(0.0, 1.0) * w;
      if (loopB > loopA) {
        canvas.drawRect(
            Rect.fromLTRB(ax, 0, loopB.clamp(0.0, 1.0) * w, h), Paint()
          ..color = accent.withAlpha(46));
      }
      void mark(double x, String t) {
        canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, h), Paint()
          ..color = Colors.white.withAlpha(200));
        final tp = TextPainter(text: TextSpan(text: t,
            style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white)), textDirection: TextDirection.ltr)
          ..layout();
        final bx = math.min(w - tp.width - 8, math.max(0.0, x + 2));
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(bx, 0, tp.width + 8, 16), const Radius.circular(5)),
            Paint()
              ..color = accent.withAlpha(210));
        tp.paint(canvas, Offset(bx + 4, 1.5));
      }
      mark(ax, 'A');
      if (loopB > loopA) mark(loopB.clamp(0.0, 1.0) * w, 'B');
    }
    if (prog > 0) {
      final x = math.min(w - 2, prog * w) - 1;
      canvas.drawRect(Rect.fromLTWH(x, h * 0.06, 2, h * 0.88), Paint()
        ..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      old.loopA != loopA || old.loopB != loopB || old.prog != prog ||
          old.accent != accent || old.playing != playing || old.tm != tm ||
          !identical(old.peaks, peaks);
}
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_state.dart';
import '../design.dart';
import '../lyrics.dart';
import '../models.dart';
import '../native.dart';
import '../widgets.dart';

/// The lyrics of the current song, in the Apple Music style: the line that is being
/// sung fills in word by word, lines that were sung stay a medium grey, and lines
/// still to come fade away further down. Tap a line to jump there.
class LyricsView extends StatefulWidget {
  final AppState state;
  final Color accent;
  final bool full; // true on the full-screen page
  final bool showHeader; // the small row with the translate and romaji buttons
  const LyricsView({super.key, required this.state, required this.accent, this.full = false, this.showHeader = true});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> with SingleTickerProviderStateMixin {
  final ScrollController _sc = ScrollController();
  List<GlobalKey> _keys = <GlobalKey>[];
  LyricsData? _seen;
  int _active = -1;
  DateTime _userUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // The position, made smooth: Android only reports it a few times a second, so the
  // words are moved on by a clock that ticks with every frame of the screen.
  final ValueNotifier<int> _nowMs = ValueNotifier<int>(0);
  Ticker? _clock;
  int _basePos = 0;
  DateTime _baseAt = DateTime.now();

  int get _now => _basePos + (s.playing ? DateTime.now().difference(_baseAt).inMilliseconds : 0);

  AppState get s => widget.state;
  LyricsController get lyr => s.lyr;

  @override
  void initState() {
    super.initState();
    _basePos = s.positionMs.value;
    _baseAt = DateTime.now();
    _nowMs.value = _basePos;
    s.positionMs.addListener(_tick);
    WidgetsBinding.instance.addPostFrameCallback((_) => lyr.ensure(s.current));
  }

  @override
  void dispose() {
    s.positionMs.removeListener(_tick);
    _clock?.dispose();
    _nowMs.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _tick() {
    // A new report from the player: slide gently towards it instead of jumping,
    // so the word fill never steps backwards.
    final p = s.positionMs.value;
    final est = _now;
    _basePos = (s.playing && (p - est).abs() < 250) ? est + ((p - est) * 0.25).round() : p;
    _baseAt = DateTime.now();
    final v = _now;
    if (v != _nowMs.value) _nowMs.value = v;
    final d = lyr.data;
    if (d == null || !d.synced || !mounted) return;
    final i = activeLine(d, v + 250);
    if (i != _active) {
      setState(() => _active = i);
      _follow(i);
    }
    _runClock(d);
  }

  /// A clock that ticks once per frame (60 or 120 times a second) and moves the words
  /// while position reports only come a few times a second. It runs only while synced
  /// lyrics are on screen and music is playing.
  void _runClock(LyricsData? d) {
    final need = mounted && d != null && d.synced && s.playing;
    if (need) {
      _clock ??= createTicker(_onFrame);
      if (!_clock!.isActive) _clock!.start();
    } else {
      if (_clock?.isActive ?? false) _clock!.stop();
      if (mounted) _nowMs.value = _now;
    }
  }

  void _onFrame(Duration _) {
    if (!mounted) return;
    if (!s.playing) {
      _runClock(lyr.data);
      return;
    }
    final v = _now;
    if (v != _nowMs.value) _nowMs.value = v;
    final dd = lyr.data;
    if (dd == null || !dd.synced) return;
    final i = activeLine(dd, v + 250);
    if (i != _active) {
      setState(() => _active = i);
      _follow(i);
    }
  }

  void _follow(int i) {
    if (i < 0 || DateTime.now().isBefore(_userUntil)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || i >= _keys.length) return;
      final c = _keys[i].currentContext;
      if (c != null) Scrollable.ensureVisible(c, alignment: widget.full ? 0.30 : 0.38, duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic);
    });
  }

  void _say(String? m) {
    if (m != null && m.isNotEmpty && mounted) toast(context, m);
  }

  Future<void> _toggleTr() async {
    s.prefs.lyrTr = !s.prefs.lyrTr;
    s.savePrefs();
    if (s.prefs.lyrTr) _say(await lyr.translate());
  }

  Future<void> _toggleRo() async {
    s.prefs.lyrRo = !s.prefs.lyrRo;
    s.savePrefs();
    if (s.prefs.lyrRo) _say(await lyr.romanize());
  }

  Future<void> _find({String? custom}) async => _say(await lyr.findOnline(custom: custom));

  // ---------------------------------------------------------------- search everywhere: the picker
  /// Searches every source at once and lets the person choose from a list.
  Future<void> _searchEverywhere({String? custom}) async {
    if (lyr.busy) return;
    if (!lyr.lyricsNetOk) {
      _say('Online lyrics search is turned off in Settings → Privacy & online.');
      return;
    }
    final hits = await lyr.search(custom: custom);
    if (!mounted || hits.isEmpty) {
      if (lyr.note.isNotEmpty) _say(lyr.note);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext b) => _HitPicker(state: this, hits: hits),
    );
  }

  /// What the picker shows for the kind of timing a result has.
  (String, IconData) _kindBadge(String kind) {
    switch (kind) {
      case 'word':
        return ('word by word', Icons.graphic_eq_rounded);
      case 'line':
        return ('synced', Icons.timer_rounded);
      default:
        return ('plain text', Icons.notes_rounded);
    }
  }

  Future<void> _search() async {
    final t = s.current;
    if (t == null) return;
    final q = await askName(context, 'Search lyrics for', '${t.title} ${t.artist}'.trim());
    if (q == null || q.trim().isEmpty) return;
    await _searchEverywhere(custom: q.trim());
  }

  /// Loads the lyrics of this song from a .lrc or .txt file on the phone (word stamps are kept).
  Future<void> _importFile() async {
    String? text;
    try {
      text = await Native.pickText();
    } catch (_) {
      text = null;
    }
    if (!mounted || text == null) return;
    if (text.trim().isEmpty) {
      toast(context, 'That file is empty or too large (limit 1 MB).');
      return;
    }
    final err = lyr.saveText(text);
    toast(context, err ?? 'Lyrics loaded from the file');
  }

  void _edit() {
    final c = TextEditingController(text: lyr.plainText);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext b) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(b).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Lyrics for this song', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Paste plain text, or LRC text with [mm:ss.xx] time stamps for synced lyrics. Word timing (<mm:ss.xx> before each word) is understood too. It is saved on this phone and used before anything else.',
              style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(128))),
          const SizedBox(height: 10),
          TextField(
            controller: c,
            maxLines: 9,
            minLines: 5,
            decoration: InputDecoration(hintText: 'Paste lyrics here', filled: true, fillColor: Colors.white.withAlpha(14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton(
              onPressed: () {
                final err = lyr.saveText(c.text);
                if (err != null) {
                  toast(b, err);
                } else {
                  Navigator.of(b).pop();
                  toast(context, 'Lyrics saved');
                }
              },
              child: const Text('Save'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: () => Navigator.of(b).pop(), child: const Text('Cancel')),
            const Spacer(),
            if (lyr.hasSaved)
              TextButton(
                onPressed: () {
                  Navigator.of(b).pop();
                  lyr.deleteSaved();
                  toast(context, 'Saved lyrics removed');
                },
                child: const Text('Delete', style: TextStyle(color: Color(0xFFFF8A80))),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([s, lyr]),
      builder: (BuildContext context, Widget? _) {
        final d = lyr.data;
        if (!identical(d, _seen)) {
          _seen = d;
          _keys = d == null ? <GlobalKey>[] : List<GlobalKey>.generate(d.lines.length, (int _) => GlobalKey());
          _active = d == null ? -1 : activeLine(d, s.positionMs.value);
          if (d != null && _active >= 0) {
            final a = _active;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && a < _keys.length && _keys[a].currentContext != null) Scrollable.ensureVisible(_keys[a].currentContext!, alignment: widget.full ? 0.30 : 0.38);
            });
          }
        }
        _runClock(d);
        return Column(children: [
          if (widget.showHeader) _header(d),
          Expanded(child: d == null ? _empty() : _lines(d)),
        ]);
      },
    );
  }

  // ---------------------------------------------------------------- the row above the lines
  Widget _header(LyricsData? d) {
    final p = s.prefs;
    final on = lighter(widget.accent);
    final off = Colors.white.withAlpha(150);
    final badge = d == null ? 'Lyrics' : (d.synced ? 'Synced lyrics' : 'Lyrics');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 0),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            Flexible(child: Text(lyr.note.isEmpty ? badge : '$badge · ${lyr.note}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(140)))),
            if (lyr.busy) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
        if (d != null) ...[
          IconButton(
            tooltip: 'Translate to ${lyr.trName}',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.translate_rounded, size: 20, color: p.lyrTr ? on : off),
            onPressed: _toggleTr,
          ),
          if (d.jp)
            IconButton(
              tooltip: 'Romaji',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.abc_rounded, size: 26, color: p.lyrRo ? on : off),
              onPressed: _toggleRo,
            ),
        ],
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: Icon(Icons.more_vert_rounded, size: 20, color: off),
          onSelected: (String v) {
            switch (v) {
              case 'edit':
                _edit();
                break;
              case 'file':
                _importFile();
                break;
              case 'find':
                _find();
                break;
              case 'pick':
                _searchEverywhere();
                break;
              case 'search':
                _search();
                break;
              case 'del':
                lyr.deleteSaved();
                break;
              case 'full':
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => LyricsPage(state: s)));
                break;
            }
          },
          itemBuilder: (BuildContext _) => [
            const PopupMenuItem<String>(value: 'edit', child: Text('Paste or edit lyrics')),
            const PopupMenuItem<String>(value: 'file', child: Text('Load a .lrc file…')),
            if (lyr.lyricsNetOk) const PopupMenuItem<String>(value: 'find', child: Text('Find lyrics online (best pick)')),
            if (lyr.lyricsNetOk) const PopupMenuItem<String>(value: 'pick', child: Text('Search everywhere and choose…')),
            if (lyr.lyricsNetOk) const PopupMenuItem<String>(value: 'search', child: Text('Search by your own words…')),
            if (lyr.hasSaved) const PopupMenuItem<String>(value: 'del', child: Text('Delete saved lyrics')),
            if (!widget.full) const PopupMenuItem<String>(value: 'full', child: Text('Full screen')),
          ],
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- no lyrics yet
  Widget _empty() {
    final loading = lyr.state == 'loading';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: loading
            ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lyrics_outlined, size: 40, color: Colors.white.withAlpha(70)),
          const SizedBox(height: 10),
          const Text('Lyrics not available', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'This song has no lyrics in its tags. Lyrics saved inside the file (MP3, AIFF, WAV, FLAC, M4A) show up here by themselves.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white.withAlpha(128)),
          ),
          const SizedBox(height: 14),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            if (lyr.lyricsNetOk)
              FilledButton.icon(
                onPressed: lyr.busy ? null : () => _searchEverywhere(),
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Search everywhere'),
              ),
            OutlinedButton.icon(onPressed: _edit, icon: const Icon(Icons.content_paste_rounded, size: 18), label: const Text('Paste lyrics')),
            if (lyr.lyricsNetOk) TextButton(onPressed: lyr.busy ? null : _search, child: const Text('By your own words…')),
          ]),
          if (lyr.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(lyr.note, style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(128)))),
          if (!lyr.lyricsNetOk)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Online lookup is off (Settings → Privacy & online).', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(100))),
            ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- the lines
  Widget _lines(LyricsData d) {
    final p = s.prefs;
    final size = p.lyrSize;
    final center = widget.full ? false : p.lyrCenter; // the full-screen page is left aligned, like Apple Music
    final cross = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final align = center ? TextAlign.center : TextAlign.left;
    final children = <Widget>[];

    for (var i = 0; i < d.lines.length; i++) {
      final l = d.lines[i];
      if (l.text.isEmpty) {
        children.add(SizedBox(key: _keys[i], height: 16 * size));
        continue;
      }
      final isOn = i == _active;
      final showTr = p.lyrTr && (l.tr ?? '').isNotEmpty;
      final showRo = p.lyrRo && (l.ro ?? '').isNotEmpty;
      final op = _lineOpacity(d, i, isOn, p.lyrSoft);

      Widget body = Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.full ? 22 : 14, vertical: (widget.full ? 11 : 9) * size),
        child: SizedBox(
          width: double.infinity,
          child: Column(crossAxisAlignment: cross, children: [
            _lineBody(d, l, isOn, size, center, align),
            if (showRo) _roBody(d, l, isOn, size, align),
            if (showTr) Padding(padding: const EdgeInsets.only(top: 3), child: Text(l.tr!, textAlign: align, style: TextStyle(fontSize: _base * 0.68 * size, height: 1.3, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(170)))),
          ]),
        ),
      );

      // 👇 NEW: Apple Music Style 3D Scale and Blur 👇
      final blurSigma = isOn ? 0.0 : (i < _active ? 1.5 : 2.5);
      final scale = isOn ? 1.06 : 1.0;
      final translateY = isOn ? -4.0 : 0.0;

      Widget animatedBody = AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..translate(0.0, translateY),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          scale: scale,
          alignment: center ? Alignment.center : Alignment.centerLeft,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: body,
          ),
        ),
      );
      // 👆 ------------------------------------------ 👆

      children.add(
        Material(
          key: _keys[i],
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: d.synced ? () => s.seekTo(l.ms!) : null,
            child: RepaintBoundary(child: AnimatedOpacity(duration: const Duration(milliseconds: 380), curve: Curves.easeOut, opacity: op, child: animatedBody)),
          ),
        ),
      );
    }

    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 80),
      child: Text(d.source, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(80))),
    ));

    return NotificationListener<ScrollStartNotification>(
      onNotification: (ScrollStartNotification n) {
        if (n.dragDetails != null) _userUntil = DateTime.now().add(const Duration(seconds: 4));
        return false;
      },
      child: ShaderMask(
        shaderCallback: (Rect r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, 0.06, 0.88, 1]).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(controller: _sc, padding: const EdgeInsets.only(top: 6), child: Column(crossAxisAlignment: cross, children: children)),
      ),
    );
  }

  double _lineOpacity(LyricsData d, int i, bool isOn, bool soft) {
    if (!d.synced) return 0.92;
    if (isOn) return 1;
    if (i < _active) return 0.42; // sung: medium grey, like Apple Music
    if (!soft) return 0.40;
    return math.max(0.40 - (i - _active) * 0.11, 0.07); // upcoming: fades away below
  }

  double get _base => widget.full ? 30.0 : 21.0;

  /// The line itself: the active one is built word by word, so each word fills in
  /// while it is sung. Every other line stays a single Text.
  Widget _lineBody(LyricsData d, LyricLine l, bool isOn, double size, bool center, TextAlign align) {
    final style = TextStyle(fontSize: _base * size, height: 1.25, fontWeight: widget.full ? FontWeight.w800 : (isOn ? FontWeight.w800 : FontWeight.w700), color: Colors.white);
    if (!isOn || !d.synced || l.words == null || l.words!.isEmpty) {
      return Text(l.text, textAlign: align, style: style);
    }
    // Japanese has no spaces between words, so the words sit right next to each other.
    final gap = hasJp(l.text) ? 0.0 : 6 * size;
    return ValueListenableBuilder<int>(
      valueListenable: _nowMs,
      builder: (BuildContext c, int now, Widget? _) => Wrap(
        spacing: gap,
        runSpacing: 4 * size,
        alignment: center ? WrapAlignment.center : WrapAlignment.start,
        children: [for (final w in l.words!) _word(w, now, style)],
      ),
    );
  }

  /// The share of the line that has been sung, 0 to 1, weighted by the length of each word.
  double _linePr(LyricLine l, int now) {
    final ws = l.words;
    if (ws == null || ws.isEmpty) return 0;
    var total = 0, got = 0.0;
    for (final w in ws) {
      final n = math.max(w.text.length, 1);
      total += n;
      got += n * w.progress(now);
    }
    return total == 0 ? 0 : got / total;
  }

  /// The gradient that wipes a text from white to a dim colour. Its edge is soft, about [feather] pixels wide.
  ui.Shader _wipe(Rect r, double p, {double feather = 40}) {
    final f = (feather / math.max(r.width, 1)).clamp(0.02, 0.6).toDouble();
    final a = (p * (1 + f) - f).clamp(0.0, 1.0).toDouble();
    final b = (p * (1 + f)).clamp(0.0, 1.0).toDouble();
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: const [Colors.white, Colors.white, Color(0x5CFFFFFF)],
      stops: [0.0, a, b],
    ).createShader(r);
  }

  /// One word, wiping from dim to white while it is sung.
  Widget _word(LyricWord w, int now, TextStyle style) {
    final pr = w.progress(now);
    if (pr >= 1) return Text(w.text, style: style); // sung: plain, cheap
    if (pr <= 0) return Text(w.text, style: style.copyWith(color: const Color(0x5CFFFFFF))); // not yet: dim, cheap
    return ShaderMask(
      shaderCallback: (Rect r) => _wipe(r, pr),
      blendMode: BlendMode.srcIn,
      child: Text(w.text, style: style),
    );
  }

  /// The romaji under a line. On the line being sung it fills in along with the words.
  Widget _roBody(LyricsData d, LyricLine l, bool isOn, double size, TextAlign align) {
    final style = TextStyle(fontSize: _base * 0.58 * size, height: 1.25, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(215));
    final text = Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(l.ro!, textAlign: align, style: style),
    );
    if (!isOn || !d.synced || l.words == null || l.words!.isEmpty) return text;
    return ValueListenableBuilder<int>(
      valueListenable: _nowMs,
      builder: (BuildContext c, int now, Widget? _) {
        final pr = _linePr(l, now);
        return Padding(
          padding: const EdgeInsets.only(top: 3),
          child: ShaderMask(
            shaderCallback: (Rect r) => _wipe(r, pr, feather: 18),
            blendMode: BlendMode.srcIn,
            child: Text(l.ro!, textAlign: align, style: style.copyWith(color: Colors.white)),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------------ the picker sheet
/// The search results from every source, with a badge for the kind of timing.
class _HitPicker extends StatelessWidget {
  final _LyricsViewState state;
  final List<LyricHit> hits;
  const _HitPicker({required this.state, required this.hits});

  @override
  Widget build(BuildContext context) {
    final accent = state.widget.accent;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Choose lyrics', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${hits.length} results · word-by-word first', style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(128))),
          ]),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 14),
            itemCount: hits.length,
            itemBuilder: (BuildContext c, int i) {
              final h = hits[i];
              final (label, icon) = state._kindBadge(h.kind);
              return ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: h.kind == 'word' ? lighter(accent).withAlpha(40) : Colors.white.withAlpha(14), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 22, color: h.kind == 'word' ? lighter(accent) : Colors.white.withAlpha(160)),
                ),
                title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                subtitle: Text(h.sub.isEmpty ? h.source : '$h.sub · ${h.source}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(140))),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: h.kind == 'word' ? lighter(accent).withAlpha(50) : Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(20)),
                  child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: h.kind == 'word' ? lighter(accent) : Colors.white.withAlpha(170))),
                ),
                onTap: () {
                  final err = state.lyr.applyHit(h);
                  Navigator.of(c).pop();
                  if (err != null) {
                    toast(context, err);
                  } else {
                    toast(context, h.kind == 'word' ? 'Word-by-word lyrics applied' : 'Lyrics applied');
                  }
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------------ the full-screen page
final Map<String, Color> _toneCache = <String, Color>{};

/// The main colour of a cover, softened, for the page background. Null when there is no cover.
Future<Color?> _coverTone(String? path) async {
  final f = coverFile(path);
  if (f == null) return null;
  final hit = _toneCache[f.path];
  if (hit != null) return hit;
  try {
    final codec = await ui.instantiateImageCodec(await f.readAsBytes(), targetWidth: 32);
    final fr = await codec.getNextFrame();
    final bd = await fr.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return null;
    double r = 0, g = 0, b = 0, w = 0;
    for (var i = 0; i + 3 < bd.lengthInBytes; i += 4) {
      final pr = bd.getUint8(i), pg = bd.getUint8(i + 1), pb = bd.getUint8(i + 2);
      final mx = math.max(pr, math.max(pg, pb)), mn = math.min(pr, math.min(pg, pb));
      final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
      final lum = mx / 255.0;
      final wt = (0.05 + sat * sat) * ((lum > 0.1 && lum < 0.95) ? 1.0 : 0.15); // colourful pixels count most
      r += pr * wt;
      g += pg * wt;
      b += pb * wt;
      w += wt;
    }
    if (w <= 0) return null;
    final c = Color.fromARGB(255, (r / w).round(), (g / w).round(), (b / w).round());
    _toneCache[f.path] = c;
    return c;
  } catch (_) {
    return null;
  }
}

/// The lyrics on the whole screen, like Apple Music: the cover colour behind, the song on top,
/// big lines that fill in word by word, and the play controls underneath.
class LyricsPage extends StatefulWidget {
  final AppState state;
  const LyricsPage({super.key, required this.state});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  final GlobalKey<_LyricsViewState> _vk = GlobalKey<_LyricsViewState>();
  AppState get s => widget.state;
  String? _toneFor;
  Color? _tone;
  int _vol = 0, _volMax = 15;
  Timer? _volTimer;
  final ValueNotifier<double?> _drag = ValueNotifier<double?>(null); // the bar position while a finger is on it

  @override
  void initState() {
    super.initState();
    _readVolume();
    _volTimer = Timer.periodic(const Duration(seconds: 2), (_) => _readVolume());
  }

  @override
  void dispose() {
    _volTimer?.cancel();
    _drag.dispose();
    super.dispose();
  }

  Future<void> _readVolume() async {
    try {
      final (cur, max) = await Native.volumeInfo();
      if (mounted && (cur != _vol || max != _volMax)) setState(() { _vol = cur; _volMax = max; });
    } catch (_) {}
  }

  Color _top(Color c) {
    final h = HSLColor.fromColor(c);
    return h.withSaturation(h.saturation.clamp(0.25, 0.55).toDouble()).withLightness(0.52).toColor();
  }

  Color _bottom(Color c) {
    final h = HSLColor.fromColor(c);
    final base = h.withSaturation(h.saturation.clamp(0.25, 0.5).toDouble()).withLightness(0.26).toColor();
    return Color.lerp(base, const Color(0xFF3A2F55), 0.35)!;
  }

  Widget _round(IconData icon, VoidCallback? onTap) {
    return Material(
      color: Colors.white.withAlpha(56),
      shape: const CircleBorder(),
      child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 50, height: 50, child: Icon(icon, size: 26, color: Colors.white))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (BuildContext context, Widget? _) {
        final accent = accentOf(s);
        final t = s.current;
        if (t?.art != _toneFor) {
          _toneFor = t?.art;
          _coverTone(t?.art).then((Color? c) {
            if (mounted) setState(() => _tone = c);
          });
        }
        final base = _tone ?? accent;
        final p = s.prefs;
        return Scaffold(
          backgroundColor: kBg,
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_top(base), _bottom(base)])),
            child: Material(
              type: MaterialType.transparency,
              child: SafeArea(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Row(children: [
                      Cover(path: t?.art, size: 60, radius: 12),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                          if ((t?.artist ?? '').isNotEmpty) Text(t!.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Colors.white.withAlpha(165))),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      _round(Icons.close_rounded, () => Navigator.of(context).maybePop()),
                      const SizedBox(width: 10),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        offset: const Offset(0, 56),
                        onSelected: (String v) {
                          final st = _vk.currentState;
                          switch (v) {
                            case 'tr':
                              st?._toggleTr();
                              break;
                            case 'ro':
                              st?._toggleRo();
                              break;
                            case 'edit':
                              st?._edit();
                              break;
                            case 'file':
                              st?._importFile();
                              break;
                            case 'find':
                              st?._find();
                              break;
                            case 'pick':
                              st?._searchEverywhere();
                              break;
                            case 'search':
                              st?._search();
                              break;
                            case 'del':
                              s.lyr.deleteSaved();
                              break;
                          }
                        },
                        itemBuilder: (BuildContext _) => [
                          PopupMenuItem<String>(value: 'tr', child: Text(p.lyrTr ? 'Hide translation' : 'Translate to ${s.lyr.trName}')),
                          if (s.lyr.data?.jp ?? false) PopupMenuItem<String>(value: 'ro', child: Text(p.lyrRo ? 'Hide romaji' : 'Show romaji')),
                          const PopupMenuItem<String>(value: 'edit', child: Text('Paste or edit lyrics')),
                          const PopupMenuItem<String>(value: 'file', child: Text('Load a .lrc file…')),
                          if (s.lyr.lyricsNetOk) const PopupMenuItem<String>(value: 'find', child: Text('Find lyrics online (best pick)')),
                          if (s.lyr.lyricsNetOk) const PopupMenuItem<String>(value: 'pick', child: Text('Search everywhere and choose…')),
                          if (s.lyr.lyricsNetOk) const PopupMenuItem<String>(value: 'search', child: Text('Search by your own words…')),
                          if (s.lyr.hasSaved) const PopupMenuItem<String>(value: 'del', child: Text('Delete saved lyrics')),
                        ],
                        child: IgnorePointer(
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(color: Colors.white.withAlpha(56), shape: BoxShape.circle),
                            child: const Icon(Icons.more_horiz_rounded, size: 26, color: Colors.white),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  Expanded(child: LyricsView(key: _vk, state: s, accent: base, full: true, showHeader: false)),
                  _seek(),
                  const SizedBox(height: 6),
                  _controls(),
                  _volume(),
                  const SizedBox(height: 14),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- progress bar and times
  Widget _seek() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
      child: ValueListenableBuilder<int>(
        valueListenable: s.positionMs,
        builder: (BuildContext c, int pos, Widget? _) => ValueListenableBuilder<double?>(
          valueListenable: _drag,
          builder: (BuildContext c2, double? dragging, Widget? _) {
            final dur = s.durationMs;
            final shown = dragging != null && dur > 0 ? (dragging * dur).round() : pos;
            final frac = dragging ?? (dur > 0 ? (pos / dur).clamp(0.0, 1.0).toDouble() : 0.0);
            return Column(children: [
              _Bar(
                value: frac,
                height: 9,
                onChanged: dur > 0 ? (double v) => _drag.value = v : null,
                onEnd: dur > 0
                    ? (double v) {
                  _drag.value = null;
                  s.seekTo((v * dur).round());
                }
                    : null,
              ),
              const SizedBox(height: 4),
              Row(children: [
                Text(fmtTime(shown), style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(150))),
                const Spacer(),
                Text('-${fmtTime((dur - shown).clamp(0, 1 << 40).toInt())}', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(150))),
              ]),
            ]);
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- previous, play, next
  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(iconSize: 54, color: Colors.white, icon: const Icon(Icons.fast_rewind_rounded), onPressed: s.prev),
        const SizedBox(width: 34),
        IconButton(iconSize: 72, color: Colors.white, icon: Icon(s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded), onPressed: s.togglePlay),
        const SizedBox(width: 34),
        IconButton(iconSize: 54, color: Colors.white, icon: const Icon(Icons.fast_forward_rounded), onPressed: s.next),
      ]),
    );
  }

  // ---------------------------------------------------------------- the phone's own volume
  Widget _volume() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () async {
            await Native.volume(0);
            _readVolume();
          },
          child: Icon(_vol == 0 ? Icons.volume_off_rounded : Icons.volume_mute_rounded, size: 24, color: Colors.white.withAlpha(165)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Bar(
            value: _volMax <= 0 ? 0.0 : (_vol / _volMax).clamp(0.0, 1.0).toDouble(),
            height: 8,
            onChanged: (double v) {
              final lv = (v * _volMax).round();
              setState(() => _vol = lv);
              Native.volumeSet(lv).catchError((Object _) {});
            },
          ),
        ),
        const SizedBox(width: 12),
        Icon(Icons.volume_up_rounded, size: 24, color: Colors.white.withAlpha(165)),
      ]),
    );
  }
}

/// A thick rounded bar you can tap or drag, used for the song position and the volume.
class _Bar extends StatelessWidget {
  final double value; // 0 to 1
  final double height;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onEnd;
  const _Bar({required this.value, required this.height, this.onChanged, this.onEnd});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext c, BoxConstraints box) {
        final w = box.maxWidth;
        double at(double dx) => w <= 0 ? 0.0 : (dx / w).clamp(0.0, 1.0).toDouble();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onChanged == null ? null : (TapDownDetails d) => onChanged!(at(d.localPosition.dx)),
          onTapUp: onEnd == null ? null : (TapUpDetails d) => onEnd!(at(d.localPosition.dx)),
          onHorizontalDragStart: onChanged == null ? null : (DragStartDetails d) => onChanged!(at(d.localPosition.dx)),
          onHorizontalDragUpdate: onChanged == null ? null : (DragUpdateDetails d) => onChanged!(at(d.localPosition.dx)),
          onHorizontalDragEnd: onEnd == null ? null : (DragEndDetails d) => onEnd!(value),
          child: SizedBox(
            height: 30,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(height),
                child: SizedBox(
                  height: height,
                  width: double.infinity,
                  child: Stack(children: [
                    Positioned.fill(child: ColoredBox(color: Colors.white.withAlpha(70))),
                    Positioned(left: 0, top: 0, bottom: 0, width: w * value.clamp(0.0, 1.0), child: ColoredBox(color: Colors.white.withAlpha(235))),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:io' show HttpClient;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // 👈 Added for Ticker
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../app_state.dart' show Prefs, kAccents;
import '../design.dart';
import '../lyrics.dart'; // 👈 Changed to import everything (LyricLine, LyricWord, hasJp)
import '../models.dart' show Track;
import '../models/yt_track.dart';
import '../services/athana_player.dart';
import '../services/yt_music_service.dart';
import '../services/yt_playlists.dart';
import '../native.dart';
import '../romanize.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fmtTime(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$sec' : '$m:$sec';
}

final List<List<YtTrack>> _cache = <List<YtTrack>>[<YtTrack>[], <YtTrack>[]];
final List<String> _cacheQ = <String>['', ''];
int _lastMode = 0; // 0 Songs, 1 Videos
String _lastText = '';

List<String> _bigCovers(YtTrack t) {
  final out = <String>[];
  final th = t.thumbnail;
  if (th != null && (th.contains('googleusercontent.com') || th.contains('ggpht.com'))) {
    final big = th.replaceAll(RegExp(r'=(w\d+-h\d+|s\d+)[^/]*$'), '=w1200-h1200-l90-rj');
    if (big != th) out.add(big);
  }
  out.add('https://i.ytimg.com/vi/${t.id}/maxresdefault.jpg');
  out.add('https://i.ytimg.com/vi/${t.id}/sddefault.jpg');
  out.add('https://i.ytimg.com/vi/${t.id}/hqdefault.jpg');
  if (th != null) out.add(th);
  return out;
}

Widget _netChain(List<String> urls, Widget Function() fallback, [int i = 0]) {
  if (i >= urls.length) return fallback();
  return Image.network(
    urls[i],
    fit: BoxFit.cover,
    filterQuality: FilterQuality.high,
    gaplessPlayback: true,
    errorBuilder: (BuildContext _, Object __, StackTrace? ___) => _netChain(urls, fallback, i + 1),
  );
}

String _coverUrl(YtTrack t) => t.thumbnail ?? 'https://i.ytimg.com/vi/${t.id}/hqdefault.jpg';

// ---------------------------------------------------------------- lyrics translation (YouTube player)
class _Gt {
  final String text, src, translit;
  const _Gt(this.text, this.src, this.translit);
}

/// Asks the same free translate endpoint that the local lyrics use. Returns null when offline or on any error.
Future<_Gt?> _gtx(String q, String tl, {String sl = 'auto', bool rm = false}) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$sl&tl=$tl&dt=t${rm ? '&dt=rm' : ''}&q=${Uri.encodeComponent(q)}';
    final req = await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 12));
    req.headers.set('User-Agent', 'Athana/2.0 (+https://github.com/Kanatahiroshi25/Athana-Release)');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    final j = jsonDecode(body);
    if (j is! List || j.isEmpty || j[0] is! List) return null;
    final text = StringBuffer(), tlit = StringBuffer();
    for (final s in j[0] as List) {
      if (s is! List) continue;
      if (s.isNotEmpty && s[0] is String) text.write(s[0]);
      if (s.length > 3 && s[3] is String) tlit.write(s[3]);
    }
    return _Gt(text.toString(), j.length > 2 && j[2] is String ? j[2] as String : '', tlit.toString());
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

String _ytHash(String s) {
  var h = 5381;
  for (final c in s.codeUnits) {
    h = ((h << 5) + h + c) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

/// Letters of any script that is not Latin: Greek, Cyrillic, Hebrew, Arabic, Indic, Thai, Georgian, kana, han, hangul.
final RegExp _nonLatin = RegExp('[\u0370-\u03FF\u0400-\u052F\u0590-\u06FF\u0700-\u074F\u0750-\u077F\u0900-\u0DFF\u0E00-\u0EFF\u0F00-\u0FFF\u1000-\u109F\u10A0-\u10FF\u1780-\u17FF\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF]');

String _ytNorm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// Which language each lyric text was translated into, so a changed language in Settings starts fresh.
final Expando<String> _trLangOf = Expando<String>('athana_yt_tr_lang');

class _YtCover extends StatelessWidget {
  final YtTrack track;
  final double size;
  final double radius;
  const _YtCover({required this.track, required this.size, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final fallback = 'https://i.ytimg.com/vi/${track.id}/hqdefault.jpg';
    Widget img(String url, Widget Function() onError) => Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (BuildContext _, Object __, StackTrace? ___) => onError(),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: img(
          _coverUrl(track),
              () => img(fallback, () => Container(color: Colors.white.withAlpha(20), child: Icon(Icons.music_note_rounded, color: Colors.white.withAlpha(120)))),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final Color accent;
  final bool on;
  final bool busy;
  final double size;
  final VoidCallback onTap;
  const _PlayButton({required this.accent, required this.on, required this.busy, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: Ink(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(accent), accent]),
          boxShadow: [BoxShadow(color: accent.withAlpha(150), blurRadius: size * 0.55, offset: Offset(0, size * 0.18), spreadRadius: -size * 0.12)],
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onTap,
          child: Center(
            child: busy
                ? SizedBox(width: size * 0.42, height: size * 0.42, child: const CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0B0B10)))
                : Icon(on ? Icons.pause_rounded : Icons.play_arrow_rounded, size: size * 0.56, color: const Color(0xFF0B0B10)),
          ),
        ),
      ),
    );
  }
}

class YtSearchScreen extends StatefulWidget {
  final Color? accent;
  final bool embedded;
  final List<YtTrack>? recommendations;
  final int? initialMode;

  const YtSearchScreen({
    super.key,
    this.accent,
    this.embedded = false,
    this.recommendations,
    this.initialMode,
  });

  @override
  State<YtSearchScreen> createState() => _YtSearchScreenState();
}

class _YtSearchScreenState extends State<YtSearchScreen> {
  final _service = YtMusicService();
  final _player = AthanaPlayer.shared;
  final _controller = TextEditingController();

  int _mode = _lastMode; // 0 Songs, 1 Videos, 2 Playlists
  List<YtTrack> get _results => _mode == 2 ? const <YtTrack>[] : _cache[_mode];
  String? _openList;
  bool _loading = false;
  bool _searched = false;
  String? _error;
  String? _opening;
  YtTrack? get _playing => _player.current;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? _lastMode;
    _controller.text = _lastText;
    _searched = _mode < 2 && _cacheQ[_mode].isNotEmpty;
    unawaited(YtPlaylists.shared.load());
    _player.now.addListener(_onNow);
    _player.askForData.addListener(_showDataDialog);
  }

  @override
  void dispose() {
    _player.now.removeListener(_onNow);
    _player.askForData.removeListener(_showDataDialog);
    _controller.dispose();
    super.dispose();
  }

  void _showDataDialog() {
    final track = _player.askForData.value;
    if (track == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF181520),
          title: const Row(children: [
            Icon(Icons.signal_cellular_alt, color: Colors.orange),
            SizedBox(width: 8),
            Text('Mobile Data', style: TextStyle(color: Colors.white)),
          ]),
          content: Text('You are using mobile data. Do you want to continue streaming "${track.title}"?', style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                _player.askForData.value = null;
                Navigator.of(context).pop();
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accent),
              onPressed: () {
                _player.askForData.value = null;
                Navigator.of(context).pop();
                _player.play(track, bypassData: true);
              },
              child: const Text('Continue', style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      },
    );
  }

  void _onNow() {
    if (mounted) setState(() {});
  }

  Color get _accent => widget.accent ?? Color(kAccents[0]);

  Future<void> _runSearch([String? q]) async {
    if (q != null) _controller.text = q;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final mode = _mode;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
    });
    try {
      final r = await _service.search(text, songs: mode == 0);
      _cache[mode] = r;
      _cacheQ[mode] = text;
      _lastText = text;
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play(YtTrack t) async {
    if (_opening != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _opening = t.id;
      _error = null;
    });
    try {
      await _player.play(t);
      if (mounted) setState(() {});
    } catch (e) {
      try {
        await _player.retry();
        if (mounted) setState(() {});
      } catch (_) {
        if (mounted) setState(() => _error = 'Could not play "${t.title}": $e');
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  void _setMode(int m) {
    if (m == _mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _mode = m;
      _lastMode = m;
      _error = null;
      _searched = m < 2 && _cacheQ[m].isNotEmpty;
    });
    if (m >= 2) return;
    final text = _controller.text.trim();
    if (text.isNotEmpty && _cacheQ[m] != text) _runSearch();
  }

  Widget _modeBar() {
    Widget item(int m, IconData icon, String label) {
      final on = _mode == m;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _setMode(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: on ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(_accent), _accent]) : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: on ? const Color(0xFF0B0B10) : Colors.white.withAlpha(150)),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: on ? const Color(0xFF0B0B10) : Colors.white.withAlpha(170))),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white.withAlpha(14), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withAlpha(22))),
        child: Row(children: [
          item(0, Icons.music_note_rounded, 'Songs'),
          item(1, Icons.smart_display_rounded, 'Videos'),
          item(2, Icons.queue_music_rounded, 'Lists'),
        ]),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(children: [
        if (_mode == 2 && _openList != null)
          IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => setState(() => _openList = null))
        else if (widget.embedded)
          const SizedBox(width: 12)
        else
          IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop()),
        const SizedBox(width: 2),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YouTube Music', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            Text(_mode == 0 ? 'Search and stream songs' : (_mode == 1 ? 'Search videos, play their sound' : 'Your own playlists'), style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(120))),
          ]),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: const Color(0xFFFF5252).withAlpha(50), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFFF5252).withAlpha(80))),
          child: const Icon(Icons.smart_display_rounded, color: Color(0xFFFF5252), size: 22),
        ),
      ]),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        decoration: glass(),
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 16),
          onChanged: (String _) => setState(() {}),
          onSubmitted: (_) => _runSearch(),
          decoration: InputDecoration(
            hintText: _mode == 0 ? 'Songs, artists, albums' : 'Search videos',
            hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
            prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(140)),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _controller.clear();
                setState(() {});
              },
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label) => Padding(
    padding: const EdgeInsets.only(right: 8, bottom: 8),
    child: Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withAlpha(26))),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _runSearch(label),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        ),
      ),
    ),
  );

  Widget _empty() {
    final recs = widget.recommendations ?? [];

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      if (recs.isNotEmpty && _mode == 0) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(6, 8, 6, 12),
          child: Text('Recommended for you', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        for (var i = 0; i < (recs.length > 6 ? 6 : recs.length); i++)
          _row(recs[i]),
      ] else ...[
        Icon(Icons.queue_music_rounded, size: 54, color: _accent.withAlpha(200)),
        const SizedBox(height: 14),
        const Text('What do you want to hear?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(_mode == 0 ? 'Type a song or an artist above.' : 'Search ordinary YouTube videos.', style: TextStyle(fontSize: 13.5, height: 1.4, color: Colors.white.withAlpha(140))),
        const SizedBox(height: 22),
        Text('TRY', style: TextStyle(fontSize: 11, letterSpacing: 3.2, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(112))),
        const SizedBox(height: 10),
        Wrap(children: [for (final s in const ['Lo-fi beats', 'Anime openings', 'Piano', 'Jazz', 'Rock hits', 'Hi-Res audio test']) _chip(s)]),
      ],
    ]);
  }

  Widget _skeleton() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: 7,
      itemBuilder: (_, int i) => Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        height: 72,
        decoration: glass(radius: 18),
        child: Row(children: [
          const SizedBox(width: 10),
          Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withAlpha(16), borderRadius: BorderRadius.circular(12))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 12, width: 190.0 - (i % 3) * 30, decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 9),
              Container(height: 10, width: 100, decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(5))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(YtTrack t) {
    final opening = _opening == t.id;
    final isPlaying = _playing?.id == t.id;
    final radius = BorderRadius.circular(18);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: isPlaying ? _accent.withAlpha(34) : Colors.white.withAlpha(12),
            borderRadius: radius,
            border: Border.all(color: isPlaying ? _accent.withAlpha(120) : Colors.white.withAlpha(20)),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: () => _play(t),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
              child: Row(children: [
                _YtCover(track: t, size: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.2, color: isPlaying ? lighter(_accent) : Colors.white)),
                    const SizedBox(height: 4),
                    Text(opening ? 'Getting the audio…' : t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(opening ? 200 : 130))),
                  ]),
                ),
                const SizedBox(width: 10),
                if (opening)
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                else if (isPlaying)
                  Icon(Icons.graphic_eq_rounded, color: lighter(_accent))
                else
                  Text(_fmtTime(t.duration), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(120))),

                ListenableBuilder(
                  listenable: YtPlaylists.shared,
                  builder: (BuildContext context, Widget? _) {
                    final inAny = YtPlaylists.shared.inAny(t.id);
                    return IconButton(
                      tooltip: 'Add to a playlist',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(inAny ? Icons.playlist_add_check_rounded : Icons.playlist_add_rounded, color: inAny ? lighter(_accent) : Colors.white.withAlpha(170)),
                      onPressed: () => showAddToPlaylist(context, t, _accent),
                    );
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playList(List<YtTrack> l, int i, {bool shuffle = false}) async {
    if (l.isEmpty || _opening != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _opening = l[i].id;
      _error = null;
    });
    try {
      await _player.playFrom(l, i, shuffle: shuffle);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not play: $e');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Widget _playlistsView() {
    return ListenableBuilder(
      listenable: YtPlaylists.shared,
      builder: (BuildContext context, Widget? _) {
        final open = _openList == null ? null : YtPlaylists.shared.byId(_openList!);
        if (open != null) return _playlistDetail(open);
        final lists = YtPlaylists.shared.lists;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          Material(
            color: Colors.transparent,
            child: Ink(
              decoration: glass(radius: 18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () async {
                  final name = await _askName(context, 'New playlist', '');
                  if (name != null) {
                    final p = await YtPlaylists.shared.create(name);
                    if (mounted) setState(() => _openList = p.id);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(_accent), _accent])),
                      child: const Icon(Icons.add_rounded, color: Color(0xFF0B0B10)),
                    ),
                    const SizedBox(width: 14),
                    const Text('New playlist', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 30, 8, 0),
              child: Column(children: [
                Icon(Icons.queue_music_rounded, size: 50, color: Colors.white.withAlpha(90)),
                const SizedBox(height: 12),
                const Text('No playlists yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Make one, then press the playlist button next to any song you find to keep it here.', textAlign: TextAlign.center, style: TextStyle(height: 1.4, color: Colors.white.withAlpha(140))),
              ]),
            ),
          for (final p in lists)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Material(
                color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withAlpha(20))),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setState(() => _openList = p.id),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(children: [
                        p.tracks.isEmpty
                            ? Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withAlpha(16), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.queue_music_rounded, color: Colors.white.withAlpha(120)))
                            : _YtCover(track: p.tracks.first, size: 56),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 3),
                            Text('${p.tracks.length} ${p.tracks.length == 1 ? 'song' : 'songs'}', style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(130))),
                          ]),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.white.withAlpha(130)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }

  Widget _playlistDetail(YtPlaylist p) {
    Widget action(IconData icon, String label, bool primary, VoidCallback? onTap) {
      final radius = BorderRadius.circular(999);
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: primary ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(_accent), _accent]) : null,
              color: primary ? null : Colors.white.withAlpha(20),
              border: primary ? null : Border.all(color: Colors.white.withAlpha(26)),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 19, color: primary ? const Color(0xFF0B0B10) : Colors.white.withAlpha(220)),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary ? const Color(0xFF0B0B10) : Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    final has = p.tracks.isNotEmpty;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text('${p.tracks.length} ${p.tracks.length == 1 ? 'song' : 'songs'}', style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(130))),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (String v) async {
            if (v == 'rename') {
              final name = await _askName(context, 'Rename playlist', p.name);
              if (name != null) await YtPlaylists.shared.rename(p.id, name);
            } else if (v == 'delete') {
              final ok = await showDialog<bool>(
                context: context,
                builder: (BuildContext c) => AlertDialog(
                  title: const Text('Delete this playlist?'),
                  content: Text('"${p.name}" will be removed from this phone. The songs themselves are not affected.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) {
                await YtPlaylists.shared.delete(p.id);
                if (mounted) setState(() => _openList = null);
              }
            }
          },
          itemBuilder: (BuildContext _) => const [
            PopupMenuItem<String>(value: 'rename', child: Text('Rename')),
            PopupMenuItem<String>(value: 'delete', child: Text('Delete playlist')),
          ],
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        action(Icons.play_arrow_rounded, 'Play', true, has ? () => _playList(p.tracks, 0) : null),
        const SizedBox(width: 10),
        action(Icons.shuffle_rounded, 'Shuffle', false, has ? () => _playList(p.tracks, 0, shuffle: true) : null),
      ]),
      const SizedBox(height: 10),
      if (!has)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 30, 8, 0),
          child: Column(children: [
            Icon(Icons.library_music_outlined, size: 46, color: Colors.white.withAlpha(90)),
            const SizedBox(height: 12),
            const Text('This playlist is empty', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Search for songs and press the playlist button next to them.', textAlign: TextAlign.center, style: TextStyle(height: 1.4, color: Colors.white.withAlpha(140))),
          ]),
        ),
      for (var i = 0; i < p.tracks.length; i++)
        Builder(builder: (BuildContext context) {
          final t = p.tracks[i];
          final isPlaying = _playing?.id == t.id;
          final opening = _opening == t.id;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  color: isPlaying ? _accent.withAlpha(34) : Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: isPlaying ? _accent.withAlpha(120) : Colors.white.withAlpha(20)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _playList(p.tracks, i),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                    child: Row(children: [
                      _YtCover(track: t, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.2, color: isPlaying ? lighter(_accent) : Colors.white)),
                          const SizedBox(height: 3),
                          Text(opening ? 'Getting the audio…' : t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(130))),
                        ]),
                      ),
                      if (opening)
                        Padding(padding: const EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _accent)))
                      else if (isPlaying)
                        Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.graphic_eq_rounded, color: lighter(_accent)))
                      else
                        Text(_fmtTime(t.duration), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(120))),

                      IconButton(
                        tooltip: 'Remove from this playlist',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close_rounded, size: 20, color: Colors.white.withAlpha(150)),
                        onPressed: () => YtPlaylists.shared.remove(p.id, t.id),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          );
        }),
    ]);
  }

  Widget _results_() {
    if (_loading && _results.isEmpty) return _skeleton();
    if (!_searched && _results.isEmpty) return _empty();
    if (_results.isEmpty) {
      return ListView(padding: const EdgeInsets.fromLTRB(22, 40, 22, 24), children: [
        Icon(Icons.search_off_rounded, size: 48, color: Colors.white.withAlpha(110)),
        const SizedBox(height: 12),
        const Text('Nothing found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Try other words, or check your internet.', style: TextStyle(color: Colors.white.withAlpha(140))),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _results.length + 1,
      itemBuilder: (_, int i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
            child: Text('${_results.length} ${_mode == 0 ? 'songs' : 'videos'}', style: TextStyle(color: Colors.white.withAlpha(112), fontSize: 12, fontWeight: FontWeight.w600)),
          );
        }
        return _row(_results[i - 1]);
      },
    );
  }

  Widget _miniPlayer() {
    final t = _playing;
    if (t == null) return const SizedBox.shrink();
    final p = _player.player;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: StreamBuilder<PlayerState>(
        stream: p.playerStateStream,
        builder: (BuildContext context, AsyncSnapshot<PlayerState> snap) {
          final st = snap.data;
          final busy = st != null && (st.processingState == ProcessingState.loading || st.processingState == ProcessingState.buffering);
          final on = st?.playing ?? false;
          return Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                color: const Color(0xE6181520),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withAlpha(30)),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (BuildContext _) => YtNowPlaying(player: _player, track: t, accent: _accent),
                )),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 12, 8),
                    child: Row(children: [
                      _YtCover(track: t, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(busy ? 'Loading…' : t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140))),
                        ]),
                      ),
                      _PlayButton(accent: _accent, on: on, busy: busy, size: 44, onTap: () => on ? _player.pause() : _player.resume()),
                    ]),
                  ),
                  StreamBuilder<Duration>(
                    stream: p.positionStream,
                    builder: (BuildContext context, AsyncSnapshot<Duration> ps) {
                      final pos = ps.data ?? Duration.zero;
                      final dur = p.duration ?? t.duration;
                      final v = dur.inMilliseconds <= 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0).toDouble();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: v, minHeight: 3, color: lighter(_accent), backgroundColor: Colors.white.withAlpha(30))),
                      );
                    },
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(children: [
      _header(),
      if (_mode != 2 && _mode != 3) _searchBox(),
      _modeBar(),
      if (_loading && _results.isNotEmpty) LinearProgressIndicator(minHeight: 2, color: _accent, backgroundColor: Colors.transparent),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
          child: Row(children: [
            const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFFF8A80)),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12.5))),
          ]),
        ),
      Expanded(
        child: _mode == 2 ? _playlistsView() : _results_(),
      ),
      _miniPlayer(),
    ]);
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: kBg,
      body: Backdrop(accent: _accent, child: SafeArea(child: content)),
    );
  }
}

Future<String?> _askName(BuildContext context, String title, String initial) async {
  final ctl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (String v) => Navigator.of(c).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(c).pop(ctl.text), child: const Text('Save')),
      ],
    ),
  );
  final t = (r ?? '').trim();
  return t.isEmpty ? null : t;
}

Future<void> showAddToPlaylist(BuildContext context, YtTrack t, Color accent) async {
  final pl = YtPlaylists.shared;
  await pl.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
        child: ListenableBuilder(
          listenable: pl,
          builder: (BuildContext c, Widget? _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
              child: const Text('Add to a playlist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(130))),
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(accent), accent])),
                child: const Icon(Icons.add_rounded, color: Color(0xFF0B0B10)),
              ),
              title: const Text('New playlist', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                final name = await _askName(c, 'New playlist', '');
                if (name == null) return;
                final p = await pl.create(name);
                await pl.toggle(p.id, t);
              },
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final p in pl.lists)
                  ListTile(
                    leading: p.tracks.isEmpty
                        ? Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withAlpha(16), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.queue_music_rounded, size: 20, color: Colors.white.withAlpha(130)))
                        : _YtCover(track: p.tracks.first, size: 40, radius: 10),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${p.tracks.length} ${p.tracks.length == 1 ? 'song' : 'songs'}'),
                    trailing: Icon(pl.contains(p.id, t.id) ? Icons.check_circle_rounded : Icons.circle_outlined, color: pl.contains(p.id, t.id) ? lighter(accent) : Colors.white.withAlpha(120)),
                    onTap: () => pl.toggle(p.id, t),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}

class YtNowPlaying extends StatefulWidget {
  final AthanaPlayer player;
  final YtTrack track;
  final Color accent;
  const YtNowPlaying({super.key, required this.player, required this.track, required this.accent});
  @override
  State<YtNowPlaying> createState() => _YtNowPlayingState();
}

class _YtNowPlayingState extends State<YtNowPlaying> with SingleTickerProviderStateMixin {
  static const double _loop = 6.981317;
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(microseconds: 6981317));
  StreamSubscription<bool>? _sub;
  String _peaksId = '';
  List<double> _peaksCache = const <double>[];
  List<double> get _peaks {
    if (_peaksId != _t.id) {
      _peaksId = _t.id;
      _peaksCache = pseudoPeaks(_t.id);
    }
    return _peaksCache;
  }

  YtTrack get _t => widget.player.current ?? widget.track;

  static final Map<String, LyricsData?> _lyrCache = <String, LyricsData?>{};
  LyricsData? _lyr;
  String _lyrState = 'loading';
  bool _lyrOpen = false;
  bool _lyrBusy = false;
  String _lyrLrc = '';
  double? _drag;
  bool _repeat = false;

  AudioPlayer get _p => widget.player.player;
  String get _link => 'https://music.youtube.com/watch?v=${_t.id}';

  @override
  void initState() {
    super.initState();
    if (_p.playing) _c.repeat();
    widget.player.now.addListener(_onTrack);
    unawaited(_fetchLyrics(_t));
    _sub = _p.playingStream.listen((bool on) {
      if (on && !_c.isAnimating) {
        _c.repeat();
      } else if (!on && _c.isAnimating) {
        _c.stop();
      }
    });
  }

  @override
  void dispose() {
    widget.player.now.removeListener(_onTrack);
    _sub?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onTrack() {
    if (!mounted) return;
    setState(() {
      _lyr = null;
      _lyrState = 'loading';
      _drag = null;
    });
    unawaited(_fetchLyrics(_t));
  }

  static String _lyrTitle(String title, String artist) {
    var s = title.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = s.split(RegExp(r'\s+[-–—]\s+'));
    if (parts.length >= 2) {
      final left = parts.first.toLowerCase();
      final a = artist.toLowerCase();
      if (a.isNotEmpty && (left.contains(a) || a.contains(left))) s = parts.sublist(1).join(' - ');
    }
    return s.isEmpty ? title : s;
  }

  Future<void> _fetchLyrics(YtTrack t) async {
    final id = t.id;
    if (_lyrCache.containsKey(id)) {
      if (mounted && _t.id == id) {
        setState(() {
          _lyr = _lyrCache[id];
          _lyrState = _lyr == null ? 'none' : 'ready';
        });
      }
      return;
    }
    LyricsData? d;
    try {
      final sp = await SharedPreferences.getInstance();
      final pr = Prefs();
      final raw = sp.getString('athana_set');
      if (raw != null) pr.load(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      if (pr.offline || !pr.netLyrics) {
        // lyrics lookup is switched off in Settings: show saved lyrics only, and do not remember "none"
        if (mounted && _t.id == id) setState(() => _lyrState = 'none');
        return;
      }
      final hits = await searchAll(_lyrTrack(t), null);
      for (final h in hits) {
        d = buildLyrics(h.lrc);
        if (d != null) {
          d.source = h.source;
          _lyrLrc = h.lrc;
          break;
        }
      }
    } catch (_) {}
    _lyrCache[id] = d;
    if (!mounted || _t.id != id) return;
    setState(() {
      _lyr = d;
      _lyrState = d == null ? 'none' : 'ready';
    });
  }

  Track _lyrTrack(YtTrack t) {
    final artist = t.artist.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();
    return Track(uri: 'youtube://${t.id}', name: '${t.title}.opus', size: 0, title: _lyrTitle(t.title, artist), artist: artist, durationMs: t.duration.inMilliseconds);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  void _applyHit(String id, LyricHit h) {
    final d = buildLyrics(h.lrc);
    if (d == null) {
      _snack('Those lyrics could not be read.');
      return;
    }
    d.source = h.source;
    _lyrCache[id] = d;
    _lyrLrc = h.lrc;
    if (!mounted || _t.id != id) return;
    setState(() {
      _lyr = d;
      _lyrState = 'ready';
    });
  }

  Future<void> _lyrBest() async {
    final id = _t.id;
    setState(() => _lyrBusy = true);
    var hits = const <LyricHit>[];
    try {
      hits = await searchAll(_lyrTrack(_t), null);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _lyrBusy = false);
    if (_t.id != id) return;
    LyricHit? pick;
    for (final h in hits) {
      if (h.lrc != _lyrLrc && buildLyrics(h.lrc) != null) {
        pick = h;
        break;
      }
    }
    if (pick == null) {
      _snack(hits.isEmpty ? 'No lyrics found online for this song.' : 'No other lyrics found.');
      return;
    }
    _applyHit(id, pick);
  }

  Future<void> _lyrChoose({String? custom}) async {
    final t = _t;
    final id = t.id;
    setState(() => _lyrBusy = true);
    var hits = const <LyricHit>[];
    try {
      hits = await searchAll(_lyrTrack(t), custom);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _lyrBusy = false);
    if (_t.id != id) return;
    if (hits.isEmpty) {
      _snack('Nothing found. Try other words.');
      return;
    }
    final accent = widget.accent;
    final pick = await showModalBottomSheet<LyricHit>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.72),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(custom == null ? 'Choose the lyrics' : 'Results for "$custom"', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: hits.length,
                itemBuilder: (BuildContext _, int i) {
                  final h = hits[i];
                  final kind = h.kind == 'word' ? 'WORD BY WORD' : (h.kind == 'line' ? 'SYNCED' : 'PLAIN');
                  return ListTile(
                    title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([if (h.sub.isNotEmpty) h.sub, h.source].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: h.kind == 'plain' ? Colors.white.withAlpha(26) : accent.withAlpha(77), borderRadius: BorderRadius.circular(6)),
                      child: Text(kind, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                    ),
                    onTap: () => Navigator.of(c).pop(h),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
    if (pick == null || !mounted || _t.id != id) return;
    _applyHit(id, pick);
  }

  Future<void> _lyrOwn() async {
    final ctl = TextEditingController(text: _lyrTitle(_t.title, _t.artist));
    final q = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Search by your own words'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'A song title, or a line of the lyrics'),
          onSubmitted: (String v) => Navigator.of(c).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(c).pop(ctl.text), child: const Text('Search')),
        ],
      ),
    );
    if (q == null || q.trim().isEmpty) return;
    await _lyrChoose(custom: q.trim());
  }

  // 👇 NEW: Custom .lrc Paste Feature 👇
  Future<void> _lyrCustom() async {
    final text = await Native.pickText(big: true);
    if (text == null || text.trim().isEmpty) return;

    final d = buildLyrics(text);
    if (d == null) {
      _snack('Those lyrics could not be read. Please check the format.');
      return;
    }

    d.source = 'Custom Import';
    _lyrCache[_t.id] = d;
    _lyrLrc = text;

    final sp = await SharedPreferences.getInstance();
    await sp.setString('athana_lyr_cache_${_t.id}', text);

    if (!mounted) return;
    setState(() {
      _lyr = d;
      _lyrState = 'ready';
    });
    _snack('Custom lyrics applied!');
  }
  // 👆 ---------------------------------- 👆

  Widget _lyricsPanel(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: glass(radius: 28),
      clipBehavior: Clip.antiAlias,
      child: _YtLyrics(
        state: _lyrState,
        data: _lyr,
        player: _p,
        accent: widget.accent,
        busy: _lyrBusy,
        onBest: _lyrBest,
        onChoose: _lyrChoose,
        onOwn: _lyrOwn,
        onCustom: _lyrCustom, // 👈 ADDED
      ),
    );
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _link));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Link copied'), behavior: SnackBarBehavior.floating));
  }

  Widget _topBar() {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          _YtRound(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Back', onTap: () => Navigator.of(context).pop()),
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
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.smart_display_rounded, size: 14, color: Color(0xFFFF5252)),
              const SizedBox(width: 6),
              const Text('YouTube', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _cover(double w, double h) {
    final t = _t;
    final accent = widget.accent;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withAlpha(26)),
        boxShadow: [BoxShadow(color: accent.withAlpha(70), blurRadius: 40, spreadRadius: -4)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(
          child: _netChain(
            _bigCovers(t),
                () => Container(
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1F1C2C), Color(0xFF928DAB)])),
              child: Icon(Icons.music_note_rounded, size: 84, color: Colors.white.withAlpha(60)),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 112,
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
              child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(204))),
            ),
          ]),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ListenableBuilder(
              listenable: YtPlaylists.shared,
              builder: (BuildContext context, Widget? _) => _YtRound(
                icon: YtPlaylists.shared.inAny(t.id) ? Icons.playlist_add_check_rounded : Icons.playlist_add_rounded,
                tooltip: 'Add to a playlist',
                onTap: () => showAddToPlaylist(context, t, accent),
              ),
            ),
            const SizedBox(width: 8),
            _YtRound(icon: Icons.link_rounded, tooltip: 'Copy link', onTap: _copyLink),
          ]),
        ),
      ]),
    );
  }

  Widget _pillRow() {
    final accent = widget.accent;
    final on = lighter(accent);
    final off = Colors.white.withAlpha(150);
    return StreamBuilder<PlayerState>(
      stream: _p.playerStateStream,
      builder: (BuildContext context, AsyncSnapshot<PlayerState> _) {
        final sleep = widget.player.sleepMinutes;
        final speed = _p.speed;
        return Row(children: [
          _YtCtl(
              icon: Icons.timer_rounded,
              label: sleep > 0 ? '${sleep}m' : '',
              color: sleep > 0 ? on : off,
              onTap: _sleepSheet
          ),
          const SizedBox(width: 6),
          _YtCtl(icon: Icons.speed_rounded, label: '$speed×', color: speed == 1.0 ? off : on, onTap: _speedSheet),
          const Spacer(),
          _YtCtl(icon: Icons.lyrics_rounded, label: '', color: _lyrOpen ? on : off, onTap: () => setState(() => _lyrOpen = !_lyrOpen)),
          const SizedBox(width: 6),
          _YtCtl(
            icon: Icons.all_inclusive_rounded,
            label: widget.player.autoplay ? 'Auto' : '',
            color: widget.player.autoplay ? on : off,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => widget.player.autoplay = !widget.player.autoplay);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(widget.player.autoplay ? 'Autoplay on: a related song plays when this one ends' : 'Autoplay off'), behavior: SnackBarBehavior.floating));
            },
          ),
          const SizedBox(width: 6),
          _YtCtl(
            icon: Icons.repeat_one_rounded,
            label: '',
            color: _repeat ? on : off,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _repeat = !_repeat);
              _p.setLoopMode(_repeat ? LoopMode.one : LoopMode.off);
            },
          ),
        ]);
      },
    );
  }

  void _speedSheet() {
    final accent = widget.accent;
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
                PillChoice(
                  label: '$r×',
                  selected: _p.speed == r,
                  accent: accent,
                  onTap: () {
                    _p.setSpeed(r);
                    Navigator.of(c).pop();
                    setState(() {});
                  },
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _sleepSheet() {
    final accent = widget.accent;
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sleep timer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('The music pauses when the time is up.', style: TextStyle(color: Colors.white.withAlpha(130))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [0, 15, 30, 45, 60, 90])
                PillChoice(
                  label: m == 0 ? 'Off' : '$m min',
                  selected: widget.player.sleepMinutes == m,
                  accent: accent,
                  onTap: () {
                    widget.player.setSleep(m);
                    Navigator.of(c).pop();
                    setState(() {});
                  },
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _waveDeck(double height) {
    final accent = widget.accent;
    final t = _t;
    return StreamBuilder<Duration>(
      stream: _p.positionStream,
      builder: (BuildContext context, AsyncSnapshot<Duration> ps) {
        final pos = ps.data ?? Duration.zero;
        final dur = _p.duration ?? t.duration;
        final ms = dur.inMilliseconds;
        final prog = (_drag ?? (ms > 0 ? pos.inMilliseconds / ms : 0.0)).clamp(0.0, 1.0).toDouble();
        final shown = Duration(milliseconds: (prog * ms).round());
        return StreamBuilder<PlayerState>(
          stream: _p.playerStateStream,
          builder: (BuildContext context, AsyncSnapshot<PlayerState> ss) {
            final st = ss.data;
            final busy = st != null && (st.processingState == ProcessingState.loading || st.processingState == ProcessingState.buffering);
            final on = st?.playing ?? false;
            return SizedBox(
              height: height,
              child: LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
                final w = box.maxWidth;
                double frac(Offset o) => w <= 0 ? 0.0 : (o.dx / w).clamp(0.0, 1.0).toDouble();
                return Stack(children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: ms > 0 ? (TapUpDetails d) => _p.seek(Duration(milliseconds: (frac(d.localPosition) * ms).round())) : null,
                      onHorizontalDragStart: ms > 0 ? (DragStartDetails d) => setState(() => _drag = frac(d.localPosition)) : null,
                      onHorizontalDragUpdate: ms > 0 ? (DragUpdateDetails d) => setState(() => _drag = frac(d.localPosition)) : null,
                      onHorizontalDragEnd: (DragEndDetails d) {
                        final f = _drag;
                        setState(() => _drag = null);
                        if (f != null && ms > 0) _p.seek(Duration(milliseconds: (f * ms).round()));
                      },
                      onHorizontalDragCancel: () => setState(() => _drag = null),
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (BuildContext context, Widget? _) => CustomPaint(painter: _YtBars(_peaks, prog, accent, on, _c.value * _loop), size: Size.infinite),
                      ),
                    ),
                  ),
                  Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _YtCirc(size: 38, icon: Icons.keyboard_double_arrow_left_rounded, iconSize: 16, dim: true, tooltip: 'Previous', onTap: () => widget.player.previous()),
                      const SizedBox(width: 8),
                      _YtCirc(size: 56, icon: Icons.replay_10_rounded, iconSize: 26, tooltip: 'Back 10 s', onTap: () => _p.seek(Duration(milliseconds: math.max(0, _p.position.inMilliseconds - 10000)))),
                      const SizedBox(width: 8),
                      AnimatedBuilder(
                        animation: _c,
                        builder: (BuildContext context, Widget? _) => _YtCirc(
                          size: 80,
                          icon: on ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          iconSize: 40,
                          busy: busy,
                          ring: lighter(accent),
                          glow: accent,
                          glowBlur: on ? 20 + 14 * (0.5 + 0.5 * math.sin(_c.value * _loop * 4.5)) : 24,
                          tooltip: on ? 'Pause' : 'Play',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            on ? widget.player.pause() : widget.player.resume();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _YtCirc(
                        size: 56,
                        icon: Icons.forward_10_rounded,
                        iconSize: 26,
                        tooltip: 'Forward 10 s',
                        onTap: () {
                          final end = ms > 0 ? ms : (1 << 30);
                          _p.seek(Duration(milliseconds: math.min(end, _p.position.inMilliseconds + 10000)));
                        },
                      ),
                      const SizedBox(width: 8),
                      _YtCirc(
                        size: 38,
                        icon: Icons.keyboard_double_arrow_right_rounded,
                        iconSize: 16,
                        dim: true,
                        tooltip: 'Next related song',
                        onTap: () async {
                          final ok = await widget.player.next();
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(const SnackBar(content: Text('No related song found right now'), behavior: SnackBarBehavior.floating));
                          }
                        },
                      ),
                    ]),
                  ),
                  Positioned(left: 4, bottom: 0, child: _YtTimePill(_fmtTime(shown))),
                  Positioned(right: 4, bottom: 0, child: _YtTimePill(_fmtTime(dur))),
                ]);
              }),
            );
          },
        );
      },
    );
  }

  Widget _formatPill() {
    final accent = widget.accent;
    final txt = TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: Colors.white.withAlpha(178));
    final parts = <String>['YOUTUBE', 'STREAMING'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: darkPill(),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: lighter(accent), shape: BoxShape.circle, boxShadow: [BoxShadow(color: accent, blurRadius: 6)])),
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) Container(width: 1, height: 10, color: Colors.white.withAlpha(46)),
          Text(parts[i], style: txt),
        ],
        Container(
          margin: const EdgeInsets.only(left: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(6)),
          child: Text('LOSSY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.white.withAlpha(153))),
        ),
      ]),
    );
  }

  Widget _upNext() {
    return ValueListenableBuilder<int>(
      valueListenable: widget.player.tick,
      builder: (BuildContext context, int _, Widget? __) {
        final n = widget.player.upNext;
        if (n == null) {
          if (!widget.player.autoplay) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(widget.player.finding ? 'Finding a related song…' : '', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white.withAlpha(120))),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: glass(radius: 18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => widget.player.next(),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                        child: Row(children: [
                          _YtCover(track: n, size: 40, radius: 10),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('UP NEXT', style: TextStyle(fontSize: 9.5, letterSpacing: 2.4, fontWeight: FontWeight.w700, color: lighter(widget.accent))),
                              const SizedBox(height: 2),
                              Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                          Icon(Icons.skip_next_rounded, color: Colors.white.withAlpha(170)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'View Queue',
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: glass(radius: 18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _showQueueSheet,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Icon(Icons.queue_music_rounded, color: Colors.white.withAlpha(200)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQueueSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext c) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (BuildContext context, ScrollController scrollController) {
            return StatefulBuilder(
                builder: (BuildContext context, StateSetter setModalState) {
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF181520),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border.all(color: Colors.white.withAlpha(20)),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: Container(
                            width: 40, height: 4,
                            decoration: BoxDecoration(color: Colors.white.withAlpha(50), borderRadius: BorderRadius.circular(2)),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Autoplay', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                    const SizedBox(height: 2),
                                    Text('Add similar content to the end of the queue', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(130))),
                                  ],
                                ),
                              ),
                              Switch(
                                value: widget.player.autoplay,
                                activeThumbColor: widget.accent,
                                onChanged: (val) {
                                  setModalState(() => widget.player.autoplay = val);
                                  setState(() => widget.player.autoplay = val);
                                  if (val) widget.player.forceAutoplayFill();
                                },
                              ),
                            ],
                          ),
                        ),
                        const Divider(color: Colors.white10),

                        Expanded(
                          child: ValueListenableBuilder<int>(
                            valueListenable: widget.player.tick,
                            builder: (BuildContext context, int _, Widget? __) {
                              final queue = widget.player.queue;
                              if (queue.isEmpty) {
                                return Center(child: Text(widget.player.autoplay ? 'Finding related songs...' : 'Queue is empty', style: const TextStyle(color: Colors.white54)));
                              }

                              return ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                itemCount: queue.length,
                                itemBuilder: (context, index) {
                                  final t = queue[index];
                                  final isNext = index == 0;
                                  final radius = BorderRadius.circular(16);

                                  return Dismissible(
                                    key: ValueKey(t.id),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        borderRadius: radius,
                                      ),
                                      child: const Icon(Icons.delete_rounded, color: Colors.white),
                                    ),
                                    onDismissed: (_) {
                                      widget.player.removeFromQueue(index);
                                      setModalState(() {});
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: Ink(
                                          decoration: BoxDecoration(
                                            color: isNext ? widget.accent.withAlpha(40) : Colors.white.withAlpha(8),
                                            borderRadius: radius,
                                            border: Border.all(color: isNext ? widget.accent.withAlpha(120) : Colors.white.withAlpha(15)),
                                          ),
                                          child: InkWell(
                                            borderRadius: radius,
                                            onTap: () {
                                              Navigator.pop(context);
                                              widget.player.playFromQueue(index);
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                                              child: Row(children: [
                                                SizedBox(
                                                    width: 32,
                                                    child: Text(
                                                        (index + 1).toString().padLeft(2, '0'),
                                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(isNext ? 200 : 100))
                                                    )
                                                ),
                                                _YtCover(track: t, size: 48, radius: 10),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                                    Row(children: [
                                                      if (isNext)
                                                        Container(
                                                          margin: const EdgeInsets.only(right: 8),
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(color: widget.accent.withAlpha(120), borderRadius: BorderRadius.circular(4)),
                                                          child: const Text('NEXT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                                                        ),
                                                      Expanded(
                                                          child: Text(
                                                              t.title,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)
                                                          )
                                                      ),
                                                    ]),
                                                    if (t.artist.isNotEmpty)
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 2),
                                                        child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(130))),
                                                      ),
                                                    if (t.duration.inSeconds > 0)
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 4),
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.timer_outlined, size: 10, color: Colors.white.withAlpha(80)),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                                _fmtTime(t.duration),
                                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white.withAlpha(90))
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ]),
                                                ),
                                                IconButton(
                                                    tooltip: 'Remove',
                                                    icon: Icon(Icons.close_rounded, size: 20, color: Colors.white.withAlpha(100)),
                                                    onPressed: () => widget.player.removeFromQueue(index)
                                                ),
                                              ]),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }
            );
          },
        );
      },
    );
  }

  Widget _portrait(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final cw = math.max(0.0, box.maxWidth - 32).toDouble();
      final coverH = math.min(cw, math.max(170.0, box.maxHeight - 430)).toDouble();
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(children: [
            _topBar(),
            _lyrOpen ? _lyricsPanel(cw, coverH) : _cover(cw, coverH),
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _pillRow()),
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _waveDeck(176)),
            const SizedBox(height: 12),
            _formatPill(),
            _upNext(),
            const SizedBox(height: 16),
          ]),
        ),
      );
    });
  }

  Widget _landscape(BuildContext context) {
    final mq = MediaQuery.of(context);
    final side = math.max(120.0, math.min(mq.size.height - mq.padding.vertical - 72, mq.size.width * 0.42)).toDouble();
    return Column(children: [
      _topBar(),
      Expanded(
        child: Row(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 8, 16), child: Align(alignment: Alignment.topCenter, child: _lyrOpen ? _lyricsPanel(side, side) : _cover(side, side))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                _pillRow(),
                const SizedBox(height: 14),
                _waveDeck(150),
                const SizedBox(height: 14),
                _formatPill(),
                _upNext(),
              ]),
            ),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final look = kLook.value;
    final mq = MediaQuery.of(context);
    final land = mq.orientation == Orientation.landscape && mq.size.width >= 560;
    return Scaffold(
      backgroundColor: kBg,
      body: Backdrop(
        accent: accent,
        child: Stack(fit: StackFit.expand, children: [
          if (!look.lite && look.wall == null && look.bg != 'minimal')
            Positioned.fill(
              child: RepaintBoundary(
                child: Opacity(
                  opacity: 0.4,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Image.network(_coverUrl(_t), fit: BoxFit.cover, cacheWidth: 160, errorBuilder: (BuildContext _, Object __, StackTrace? ___) => const SizedBox.shrink()),
                  ),
                ),
              ),
            ),
          SafeArea(child: land ? _landscape(context) : _portrait(context)),
        ]),
      ),
    );
  }
}

class _YtRound extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _YtRound({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Ink(
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withAlpha(110), border: Border.all(color: Colors.white.withAlpha(26))),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 20, color: Colors.white.withAlpha(204)))),
        ),
      ),
    );
  }
}

class _YtCtl extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _YtCtl({required this.icon, required this.label, required this.color, required this.onTap});

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

class _YtTimePill extends StatelessWidget {
  final String text;
  const _YtTimePill(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: darkPill(),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
  );
}

class _YtCirc extends StatelessWidget {
  final double size, iconSize;
  final IconData icon;
  final bool busy, dim;
  final Color? ring, glow;
  final double? glowBlur;
  final String tooltip;
  final VoidCallback onTap;
  const _YtCirc({required this.size, required this.icon, required this.iconSize, required this.tooltip, required this.onTap, this.busy = false, this.dim = false, this.ring, this.glow, this.glowBlur});

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
            child: SizedBox(
              width: size,
              height: size,
              child: busy
                  ? Padding(padding: EdgeInsets.all(size * 0.3), child: const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Icon(icon, size: iconSize, color: Colors.white.withAlpha(dim ? 150 : 255)),
            ),
          ),
        ),
      ),
    );
  }
}

class _YtBars extends CustomPainter {
  final List<double> peaks;
  final double prog;
  final Color accent;
  final bool playing;
  final double tm;
  const _YtBars(this.peaks, this.prog, this.accent, this.playing, this.tm);

  @override
  void paint(Canvas canvas, Size size) {
    const bw = 5.0, gap = 4.0;
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0 || peaks.isEmpty) return;
    final n = math.max(1, ((w + gap) / (bw + gap)).floor());
    final played = Paint()..color = accent.withAlpha(242);
    final glow = Paint()
      ..color = accent.withAlpha(110)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final rest = Paint()..color = Colors.white.withAlpha(179);
    for (var i = 0; i < n; i++) {
      final a = (i / n * peaks.length).floor();
      final b = math.max(a + 1, ((i + 1) / n * peaks.length).floor());
      var v = 0.0;
      for (var k = a; k < b && k < peaks.length; k++) {
        v = math.max(v, peaks[k]);
      }
      v = math.max(0.06, v);
      final dist = ((i + 0.5) - prog * n).abs();
      final bounce = playing && dist < 7 ? 1 + 0.2 * math.sin(tm * 9 - i * 0.7) * (1 - dist / 7) : 1.0;
      final bh = math.min(h, math.max(6.0, v * h * 0.9) * bounce);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(i * (bw + gap), (h - bh) / 2, bw, bh), const Radius.circular(2));
      final done = (i + 0.5) / n <= prog;
      if (done) canvas.drawRRect(r, glow);
      canvas.drawRRect(r, done ? played : rest);
    }
    if (prog > 0) {
      final x = math.min(w - 2, prog * w) - 1;
      canvas.drawRect(Rect.fromLTWH(x, h * 0.06, 2, h * 0.88), Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _YtBars old) => old.prog != prog || old.accent != accent || old.playing != playing || old.tm != tm || !identical(old.peaks, peaks);
}

class _YtLyrics extends StatefulWidget {
  final String state;
  final LyricsData? data;
  final AudioPlayer player;
  final Color accent;
  final bool busy;
  final VoidCallback onBest, onOwn, onCustom;
  final Future<void> Function({String? custom}) onChoose;
  const _YtLyrics({
    required this.state,
    required this.data,
    required this.player,
    required this.accent,
    required this.busy,
    required this.onBest,
    required this.onChoose,
    required this.onOwn,
    required this.onCustom,
  });
  @override
  State<_YtLyrics> createState() => _YtLyricsState();
}

class _YtLyricsState extends State<_YtLyrics> with SingleTickerProviderStateMixin {
  final ScrollController _sc = ScrollController();
  List<GlobalKey> _keys = <GlobalKey>[];
  StreamSubscription<Duration>? _sub;
  int _active = -1;
  DateTime _userUntil = DateTime.fromMillisecondsSinceEpoch(0);

  final ValueNotifier<int> _nowMs = ValueNotifier<int>(0);

  // translation + romaji
  bool _showTr = false, _showRo = false;
  bool _trBusy = false, _roBusy = false;
  String? _lang; // the language picked here; null follows Settings → Lyrics
  String _defLang = 'id';
  int _gen = 0;
  Ticker? _clock;
  int _basePos = 0;
  DateTime _baseAt = DateTime.now();

  AudioPlayer get _p => widget.player;
  bool get _playing => _p.playing;
  int get _now => _basePos + (_playing ? DateTime.now().difference(_baseAt).inMilliseconds : 0);

  @override
  void initState() {
    super.initState();
    _basePos = _p.position.inMilliseconds;
    _baseAt = DateTime.now();
    _nowMs.value = _basePos;
    _sub = _p.positionStream.listen(_tick);
    unawaited(_loadToggles());
  }

  Future<void> _loadToggles() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final tr = sp.getBool('athana_yt_show_tr') ?? false;
      final ro = sp.getBool('athana_yt_show_ro') ?? false;
      final pickedRaw = sp.getString('athana_yt_trlang');
      final picked = (pickedRaw != null && kTrLangs.containsKey(pickedRaw)) ? pickedRaw : null;
      final def = (await _prefs(sp)).trLang;
      if (!mounted) return;
      setState(() {
        _showTr = tr;
        _showRo = ro;
        _lang = picked;
        _defLang = def;
      });
      _afterData();
    } catch (_) {}
  }

  Future<void> _saveToggles() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('athana_yt_show_tr', _showTr);
      await sp.setBool('athana_yt_show_ro', _showRo);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _YtLyrics old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data)) {
      _active = -1;
      _keys = <GlobalKey>[];
      _gen++;
      _trBusy = false;
      _roBusy = false;
      _afterData();
    }
  }

  /// New lyrics arrived: fill in the translation / romaji straight away when those are switched on.
  void _afterData() {
    final d = widget.data;
    if (d == null || d.lines.isEmpty) return;
    if (_showTr) unawaited(_translate());
    if (_showRo) unawaited(_romanize());
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<Prefs> _prefs(SharedPreferences sp) async {
    final pr = Prefs();
    try {
      final s = sp.getString('athana_set');
      if (s != null) pr.load(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {}
    return pr;
  }

  void _toggleTr() {
    setState(() => _showTr = !_showTr);
    unawaited(_saveToggles());
    if (_showTr) unawaited(_translate());
  }

  void _toggleRo() {
    setState(() => _showRo = !_showRo);
    unawaited(_saveToggles());
    if (_showRo) unawaited(_romanize());
  }

  Future<void> _pickLang() async {
    final cur = _lang ?? _defLang;
    final accent = widget.accent;
    final h = MediaQuery.of(context).size.height;
    final pick = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16131F),
      constraints: BoxConstraints(maxHeight: h * 0.7),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 14),
          Text('TRANSLATE LYRICS INTO', style: TextStyle(fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(128))),
          const SizedBox(height: 6),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final e in kTrLangs.entries)
                ListTile(
                  title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: e.key == cur ? Icon(Icons.check_rounded, color: lighter(accent)) : null,
                  onTap: () => Navigator.of(c).pop(e.key),
                ),
              const SizedBox(height: 8),
            ]),
          ),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    setState(() {
      _lang = pick;
      _showTr = true;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('athana_yt_trlang', pick);
    } catch (_) {}
    unawaited(_saveToggles());
    unawaited(_translate());
  }

  void _turnOffTr(String msg) {
    if (mounted) setState(() => _showTr = false);
    unawaited(_saveToggles());
    _snack(msg);
  }

  Future<void> _translate() async {
    final d = widget.data;
    if (d == null || d.lines.isEmpty || _trBusy) return;
    final sp = await SharedPreferences.getInstance();
    final pr = await _prefs(sp);
    _defLang = pr.trLang;
    final lang = _lang ?? pr.trLang;
    final name = kTrLangs[lang] ?? lang;
    if (_trLangOf[d] != lang) {
      for (final l in d.lines) {
        l.tr = null;
      }
      _trLangOf[d] = lang;
    }
    final key = 'athana_yt_tr:$lang:${_ytHash(d.lines.map((LyricLine l) => l.text).join('\n'))}';
    try {
      final c = sp.getString(key);
      if (c != null) {
        final j = jsonDecode(c);
        if (j is List && j.length == d.lines.length) {
          for (var i = 0; i < d.lines.length; i++) {
            final v = j[i];
            if (d.lines[i].text.isNotEmpty && v is String && d.lines[i].tr == null) d.lines[i].tr = v;
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    final todo = <int>[for (var i = 0; i < d.lines.length; i++) if (d.lines[i].text.isNotEmpty && d.lines[i].tr == null) i];
    if (todo.isEmpty) return;
    if (pr.offline || !pr.netTranslate) {
      _turnOffTr('Translation is turned off in Settings → Privacy & online.');
      return;
    }
    final gen = _gen;
    setState(() => _trBusy = true);

    final chunks = <List<int>>[];
    var cur = <int>[];
    var len = 0;
    for (final i in todo) {
      final n = Uri.encodeComponent(d.lines[i].text).length + 3;
      if (cur.isNotEmpty && len + n > 1400) {
        chunks.add(cur);
        cur = <int>[];
        len = 0;
      }
      cur.add(i);
      len += n;
    }
    if (cur.isNotEmpty) chunks.add(cur);

    var done = 0;
    String? msg;
    for (var c = 0; c < chunks.length; c++) {
      if (gen != _gen || !mounted || !_showTr) break;
      final ch = chunks[c];
      final texts = <String>[for (final i in ch) d.lines[i].text.replaceAll(RegExp(r'\s*\n\s*'), ' ')];
      List<String?>? out;
      final r = await _gtx(texts.join('\n'), lang);
      if (gen != _gen || !mounted) break;
      if (r != null) {
        if (r.src == lang && c == 0) {
          for (final i in todo) {
            d.lines[i].tr = '';
          }
          msg = 'These lyrics are already in $name.';
          break;
        }
        final parts = r.text.split('\n').map((String x) => x.trim()).toList();
        while (parts.length > texts.length && parts.last.isEmpty) {
          parts.removeLast();
        }
        if (parts.length == texts.length) out = parts;
      }
      if (out == null) {
        out = <String?>[];
        for (final tx in texts) {
          final one = await _gtx(tx, lang);
          out.add(one?.text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim());
        }
        if (gen != _gen || !mounted) break;
      }
      for (var k = 0; k < ch.length; k++) {
        final v = out[k];
        if (v == null) continue;
        final f = lang == 'id' ? casualId(v) : v;
        d.lines[ch[k]].tr = _ytNorm(f) == _ytNorm(texts[k]) ? '' : f;
        done++;
      }
      setState(() {});
      if (done == 0) break;
    }
    if (gen != _gen || !mounted) return;
    setState(() => _trBusy = false);
    final all = d.lines.every((LyricLine l) => l.text.isEmpty || l.tr != null);
    if (all) {
      try {
        await sp.setString(key, jsonEncode(<String>[for (final l in d.lines) l.tr ?? '']));
      } catch (_) {}
    } else if (done == 0 && msg == null) {
      msg = 'Could not translate. Check your internet connection.';
    }
    if (msg != null) _snack(msg);
  }

  bool get _canRomaji {
    final d = widget.data;
    return d != null && d.lines.any((LyricLine l) => _nonLatin.hasMatch(l.text));
  }

  /// Which language a line is in, from its letters: 'ja' (has kana), 'ko', 'zh' (only han characters), or 'x' (any other non-Latin script, for example Russian, Arabic, Thai, Greek, Hindi).
  static String _scriptOf(String t) {
    if (hasJp(t) && RegExp('[\u3040-\u30FF]').hasMatch(t)) return 'ja';
    if (hasHangul(t)) return 'ko';
    if (RegExp('[\u3400-\u9FFF]').hasMatch(t)) return 'zh';
    return 'x';
  }

  Future<void> _romanize() async {
    final d = widget.data;
    if (d == null || d.lines.isEmpty || _roBusy) return;
    final sp = await SharedPreferences.getInstance();
    final pr = await _prefs(sp);
    final netOk = !pr.offline && pr.netTranslate;
    final key = 'athana_yt_ro2:${_ytHash(d.lines.map((LyricLine l) => l.text).join('\n'))}';
    try {
      final c = sp.getString(key);
      if (c != null) {
        final j = jsonDecode(c);
        if (j is List && j.length == d.lines.length) {
          for (var i = 0; i < d.lines.length; i++) {
            final v = j[i];
            if (v is String && v.isNotEmpty && d.lines[i].ro == null) d.lines[i].ro = v;
          }
        }
      }
    } catch (_) {}
    var own = 0, needNet = 0;
    final web = <int>[];
    final sl = <int, String>{};
    for (var i = 0; i < d.lines.length; i++) {
      final text = d.lines[i].text;
      if (text.isEmpty || d.lines[i].ro != null || !_nonLatin.hasMatch(text)) continue;
      final kind = _scriptOf(text);
      // Japanese and Chinese need a dictionary, and so does everything that is not Korean, so those use the online service
      if (kind != 'ko' && netOk) {
        web.add(i);
        sl[i] = kind == 'ja' ? 'ja' : (kind == 'zh' ? 'zh-CN' : 'auto');
        continue;
      }
      final r = romanizeOffline(text);
      if (r != null && r.isNotEmpty) {
        d.lines[i].ro = r;
        own++;
      } else {
        needNet++;
      }
    }
    if (!mounted) return;
    setState(() {});
    var done = 0;
    if (web.isNotEmpty) {
      final gen = _gen;
      setState(() => _roBusy = true);
      var next = 0;
      Future<void> worker() async {
        while (gen == _gen && mounted && _showRo) {
          final k = next++;
          if (k >= web.length) return;
          final i = web[k];
          final r = await _gtx(d.lines[i].text, 'en', sl: sl[i] ?? 'auto', rm: true);
          var v = r?.translit.trim() ?? '';
          if (v.isEmpty && r == null) v = romanizeOffline(d.lines[i].text) ?? '';
          if (v.isNotEmpty) {
            d.lines[i].ro = v[0].toUpperCase() + v.substring(1);
            done++;
            if (done % 4 == 0 && mounted) setState(() {});
          } else if (r != null) {
            d.lines[i].ro = '';
          } else {
            needNet++;
          }
        }
      }

      await Future.wait(<Future<void>>[for (var w = 0; w < 4; w++) worker()]);
      if (gen != _gen || !mounted) return;
      setState(() => _roBusy = false);
    }
    if (done + own > 0) {
      try {
        await sp.setString(key, jsonEncode(<String>[for (final l in d.lines) l.ro ?? '']));
      } catch (_) {}
    }
    if (mounted) setState(() {});
    if (needNet > 0 && done + own == 0) {
      _snack(netOk ? 'Could not get the pronunciation. Check your internet connection.' : 'Pronunciation for this language needs the online service. Turn on "Translate lyrics online" in Settings → Privacy & online.');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.dispose();
    _nowMs.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _tick(Duration p) {
    final est = _now;
    _basePos = (_playing && (p.inMilliseconds - est).abs() < 250) ? est + ((p.inMilliseconds - est) * 0.25).round() : p.inMilliseconds;
    _baseAt = DateTime.now();
    final v = _now;
    if (v != _nowMs.value) _nowMs.value = v;
    final d = widget.data;
    if (d == null || !d.synced || !mounted) return;
    final i = activeLine(d, v + 250);
    if (i != _active) {
      setState(() => _active = i);
      _follow(i);
    }
    _runClock(d);
  }

  void _runClock(LyricsData? d) {
    final need = mounted && d != null && d.synced && _playing;
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
    if (!_playing) {
      _runClock(widget.data);
      return;
    }
    final v = _now;
    if (v != _nowMs.value) _nowMs.value = v;
    final dd = widget.data;
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
      if (c != null) Scrollable.ensureVisible(c, alignment: 0.4, duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic);
    });
  }

  Widget _toolbar() {
    final accent = widget.accent;
    Widget circle(IconData icon, bool enabled, {bool on = false}) => Ink(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? accent.withAlpha(110) : Colors.black.withAlpha(90),
        border: Border.all(color: on ? lighter(accent).withAlpha(150) : Colors.white.withAlpha(26)),
      ),
      child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 18, color: on ? Colors.white : Colors.white.withAlpha(enabled ? 210 : 80))),
    );
    Widget btn(IconData icon, String tip, VoidCallback? onTap, {bool on = false, VoidCallback? onLong}) => Tooltip(
      message: tip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, onLongPress: onLong, child: circle(icon, onTap != null, on: on)),
      ),
    );
    PopupMenuItem<int> item(int v, IconData icon, String label) => PopupMenuItem<int>(
      value: v,
      child: Row(children: [Icon(icon, size: 19, color: lighter(accent)), const SizedBox(width: 12), Text(label, style: const TextStyle(fontWeight: FontWeight.w600))]),
    );
    final free = !widget.busy;
    final hasLines = widget.data != null && widget.data!.lines.isNotEmpty;
    final working = widget.busy || _trBusy || _roBusy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 0),
      child: Row(children: [
        Text('LYRICS', style: TextStyle(fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(128))),
        const SizedBox(width: 10),
        if (working) SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: lighter(accent))),
        const Spacer(),
        if (hasLines) ...[
          btn(Icons.translate_rounded, _showTr ? 'Hide translation' : 'Translate to ${kTrLangs[_lang ?? _defLang] ?? (_lang ?? _defLang)} (hold to change)', _toggleTr, on: _showTr, onLong: _pickLang),
          const SizedBox(width: 6),
        ],
        if (hasLines && _canRomaji) ...[
          btn(Icons.spellcheck_rounded, _showRo ? 'Hide pronunciation' : 'Show pronunciation', _toggleRo, on: _showRo),
          const SizedBox(width: 6),
        ],
        PopupMenuButton<int>(
          tooltip: 'Find other lyrics',
          enabled: free,
          offset: const Offset(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (int v) {
            switch (v) {
              case 0:
                widget.onBest();
                break;
              case 1:
                widget.onChoose();
                break;
              case 2:
                widget.onOwn();
                break;
              case 3:
                widget.onCustom();
                break;
              case 4:
                unawaited(_pickLang());
                break;
            }
          },
          itemBuilder: (BuildContext _) => [
            item(4, Icons.language_rounded, 'Translation language: ${kTrLangs[_lang ?? _defLang] ?? (_lang ?? _defLang)}'),
            item(0, Icons.auto_fix_high_rounded, 'Find online (best pick)'),
            item(1, Icons.manage_search_rounded, 'Search everywhere and choose'),
            item(2, Icons.edit_note_rounded, 'Search by your own words'),
            item(3, Icons.paste_rounded, 'Paste custom .lrc'),
          ],
          child: circle(Icons.more_horiz_rounded, free),
        ),
      ]),
    );
  }

  Widget _frame(Widget body) => Column(children: [_toolbar(), Expanded(child: body)]);

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    _runClock(d);
    if (widget.state == 'loading') {
      return _frame(Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: lighter(widget.accent))),
          const SizedBox(height: 14),
          Text('Looking for the lyrics…', style: TextStyle(color: Colors.white.withAlpha(150))),
        ]),
      ));
    }
    if (d == null || d.lines.isEmpty) {
      Widget pill(IconData icon, String label, VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withAlpha(26))),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: widget.busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 17, color: lighter(widget.accent)),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
      return _frame(Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lyrics_outlined, size: 44, color: Colors.white.withAlpha(90)),
            const SizedBox(height: 12),
            const Text('No lyrics found for this song', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Search by hand:', style: TextStyle(color: Colors.white.withAlpha(130))),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              pill(Icons.auto_fix_high_rounded, 'Best pick', widget.onBest),
              pill(Icons.manage_search_rounded, 'Choose', () => widget.onChoose()),
              pill(Icons.edit_note_rounded, 'My own words', widget.onOwn),
            ]),
          ]),
        ),
      ));
    }
    if (_keys.length != d.lines.length) _keys = List<GlobalKey>.generate(d.lines.length, (_) => GlobalKey());

    return _frame(NotificationListener<ScrollStartNotification>(
      onNotification: (ScrollStartNotification n) {
        if (n.dragDetails != null) _userUntil = DateTime.now().add(const Duration(seconds: 4));
        return false;
      },
      child: ShaderMask(
        shaderCallback: (Rect r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, 0.06, 0.88, 1]).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          controller: _sc,
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 90),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < d.lines.length; i++)
              Builder(builder: (context) {
                final l = d.lines[i];
                final isOn = i == _active;
                final isPast = i < _active;
                final op = isOn ? 1.0 : (isPast ? 0.42 : math.max(0.40 - (i - _active) * 0.11, 0.07));
                final blurSigma = isOn ? 0.0 : (isPast ? 1.5 : 2.5);
                final scale = isOn ? 1.06 : 1.0;
                final translateY = isOn ? -4.0 : 0.0;

                Widget body = Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: _lineBody(d, l, isOn),
                );

                return Material(
                  key: _keys[i],
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: d.synced ? () => _p.seek(Duration(milliseconds: l.ms!)) : null,
                    child: RepaintBoundary(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOut,
                        opacity: op,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          transform: Matrix4.identity()..translate(0.0, translateY),
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            scale: scale,
                            alignment: Alignment.centerLeft,
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                              child: body,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            if (d.source.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 18), child: Text('Lyrics: ${d.source}', style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(110)))),
          ]),
        ),
      ),
    ));
  }

  Widget _lineBody(LyricsData d, LyricLine l, bool isOn) {
    final main = _mainLine(d, l, isOn);
    final ro = _showRo && l.ro != null && l.ro!.isNotEmpty;
    final tr = _showTr && l.tr != null && l.tr!.isNotEmpty;
    if (!ro && !tr) return main;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      main,
      if (ro)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(l.ro!, style: TextStyle(fontSize: 14, height: 1.25, fontWeight: FontWeight.w600, color: lighter(widget.accent).withAlpha(isOn ? 255 : 200))),
        ),
      if (tr)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(l.tr!, style: TextStyle(fontSize: 15, height: 1.25, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(isOn ? 215 : 160))),
        ),
    ]);
  }

  Widget _mainLine(LyricsData d, LyricLine l, bool isOn) {
    final style = TextStyle(fontSize: 22, height: 1.25, fontWeight: isOn ? FontWeight.w800 : FontWeight.w700, color: Colors.white);
    if (!isOn || !d.synced || l.words == null || l.words!.isEmpty) {
      return Text(l.text.isEmpty ? '♪' : l.text, style: style);
    }
    final gap = hasJp(l.text) ? 0.0 : 6.0;
    return ValueListenableBuilder<int>(
      valueListenable: _nowMs,
      builder: (BuildContext c, int now, Widget? _) => Wrap(
        spacing: gap,
        runSpacing: 4.0,
        alignment: WrapAlignment.start,
        children: [for (final w in l.words!) _word(w, now, style)],
      ),
    );
  }

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

  Widget _word(LyricWord w, int now, TextStyle style) {
    final pr = w.progress(now);
    if (pr >= 1) return Text(w.text, style: style);
    if (pr <= 0) return Text(w.text, style: style.copyWith(color: const Color(0x5CFFFFFF)));
    return ShaderMask(
      shaderCallback: (Rect r) => _wipe(r, pr),
      blendMode: BlendMode.srcIn,
      child: Text(w.text, style: style),
    );
  }
}
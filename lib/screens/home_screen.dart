import 'dart:async';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:dart_ytmusic_api/types.dart';
import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart' show kAccents;
import '../design.dart';
import '../models/yt_track.dart';
import '../services/athana_player.dart';
import '../services/yt_music_service.dart';
import '../services/yt_playlists.dart';
import 'yt_search_screen.dart' show YtNowPlaying, showAddToPlaylist;

class _Mood {
  final String label;
  final IconData icon;
  final Color color;
  const _Mood(this.label, this.icon, this.color);
}

const List<_Mood> _moods = <_Mood>[
  _Mood('Feel good', Icons.wb_sunny_rounded, Color(0xFFFFC857)),
  _Mood('Sad', Icons.water_drop_rounded, Color(0xFF6EA8FF)),
  _Mood('Energize', Icons.bolt_rounded, Color(0xFFFF7A59)),
  _Mood('Relax', Icons.spa_rounded, Color(0xFF5BE3A8)),
  _Mood('Romance', Icons.favorite_rounded, Color(0xFFFF6FA5)),
  _Mood('Party', Icons.celebration_rounded, Color(0xFFB388FF)),
  _Mood('Workout', Icons.fitness_center_rounded, Color(0xFFFF5252)),
  _Mood('Focus', Icons.center_focus_strong_rounded, Color(0xFF4DD0E1)),
  _Mood('Sleep', Icons.bedtime_rounded, Color(0xFF7986CB)),
  _Mood('Commute', Icons.directions_car_rounded, Color(0xFFFFB74D)),
];

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Late night listening';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

const String _recentKey = 'athana_yt_recent';
const String _playsKey = 'athana_yt_plays';
const int _oftenMin = 3; // a song must be listened to this many times to count as "often listened"
const int _playsKeep = 300; // how many songs the app remembers counts for
const int _listenSeconds = 30; // a song counts as listened after this many seconds of playing

/// How many times a song was listened to, and when last.
class _Play {
  YtTrack track;
  int count;
  int last; // milliseconds since 1970
  _Play(this.track, this.count, this.last);
}
const int _quickMax = 12; // most songs in Quick picks
const int _quickRows = 4; // rows in one page

class HomeScreen extends StatefulWidget {
  final Color? accent;
  const HomeScreen({super.key, this.accent});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final YTMusic _ytMusic = YTMusic();
  final _player = AthanaPlayer.shared;
  final _controller = TextEditingController();

  // Home Feed Data
  bool _isLoading = true;
  bool _failed = false;
  bool _offline = false; // Offline mode is on, so nothing is loaded from YouTube
  List<HomeSection> _sections = <HomeSection>[];
  List<YtTrack> _recent = <YtTrack>[];

  // Search Data
  int _mode = 0; // 0 Songs, 1 Videos, 2 Lists
  List<List<YtTrack>> _cache = [<YtTrack>[], <YtTrack>[]];
  List<String> _cacheQ = ['', ''];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  String? _opening;
  String? _openList;
  bool _searchFocus = false;
  // search-as-you-type: suggested searches and a few songs, like YouTube Music
  List<String> _sugg = <String>[];
  List<YtTrack> _suggTracks = <YtTrack>[];
  Timer? _suggTimer;
  int _suggGen = 0;
  final PageController _quickCtl = PageController(viewportFraction: 0.92);
  int _quickPage = 0;
  final Map<String, _Play> _plays = <String, _Play>{}; // song id -> how often it was listened to
  Timer? _listenTimer;

  Color get _accent => widget.accent ?? Color(kAccents[0]);

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadPlays();
    _player.now.addListener(_onNow);
    _player.askForData.addListener(_showDataDialog);
    _loadHomeFeed();
    unawaited(YtPlaylists.shared.load());
  }

  @override
  void dispose() {
    _player.now.removeListener(_onNow);
    _player.askForData.removeListener(_showDataDialog);
    _controller.dispose();
    _listenTimer?.cancel();
    _suggTimer?.cancel();
    _quickCtl.dispose();
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

  // ------------------------------------------------------------------ Data Loaders

  Future<void> _loadHomeFeed() async {
    if (await YtMusicService.isOffline()) {
      if (!mounted) return;
      setState(() {
        _offline = true;
        _isLoading = false;
        _failed = _sections.isEmpty;
      });
      return;
    }
    if (_offline && mounted) setState(() => _offline = false);
    try {
      await _ytMusic.initialize();
      final sections = await _ytMusic.getHomeSections();
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _isLoading = false;
        _failed = sections.isEmpty;
      });
    } catch (e) {
      debugPrint('Error loading home: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _failed = _sections.isEmpty;
        });
      }
    }
  }

  // ---- Quick picks: the songs you listen to often

  Future<void> _loadPlays() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_playsKey);
      if (raw == null) return;
      final map = <String, _Play>{};
      for (final dynamic e in (jsonDecode(raw) as List<dynamic>)) {
        final m = Map<String, dynamic>.from(e as Map);
        final t = YtTrack.fromJson(Map<String, dynamic>.from(m['t'] as Map));
        map[t.id] = _Play(t, (m['c'] as num).toInt(), (m['l'] as num).toInt());
      }
      if (mounted) {
        setState(() {
          _plays
            ..clear()
            ..addAll(map);
        });
      }
    } catch (_) {
      // a damaged list is simply forgotten
    }
  }

  Future<void> _savePlays() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = _plays.values.map((_Play e) => <String, dynamic>{'t': e.track.toJson(), 'c': e.count, 'l': e.last}).toList();
      await p.setString(_playsKey, jsonEncode(list));
    } catch (_) {}
  }

  /// Called when a song has played for [_listenSeconds] seconds: that is one listen.
  void _countListen(YtTrack t) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = _plays[t.id];
    _plays[t.id] = _Play(t, (old?.count ?? 0) + 1, now);
    if (_plays.length > _playsKeep) {
      // forget the songs listened to least, and longest ago
      final all = _plays.values.toList()
        ..sort((_Play a, _Play b) => a.count != b.count ? a.count.compareTo(b.count) : a.last.compareTo(b.last));
      for (final e in all.take(_plays.length - _playsKeep)) {
        _plays.remove(e.track.id);
      }
    }
    if (mounted) setState(() {});
    unawaited(_savePlays());
  }

  /// The songs listened to at least [_oftenMin] times, the most listened first.
  List<_Play> _oftenListened() {
    final list = _plays.values.where((_Play e) => e.count >= _oftenMin).toList()
      ..sort((_Play a, _Play b) => a.count != b.count ? b.count.compareTo(a.count) : b.last.compareTo(a.last));
    return list;
  }

  /// The songs of Quick picks, at most [_quickMax]. Your often listened songs come first (they are remembered on
  /// the phone, so they show at once). Left-over places are filled with YouTube's own quick picks, which are not saved.
  List<YtTrack> _quickList() {
    final out = <YtTrack>[];
    final seen = <String>{};
    void add(Iterable<YtTrack> src) {
      for (final t in src) {
        if (out.length >= _quickMax) return;
        if (t.id.isNotEmpty && seen.add(t.id)) out.add(t);
      }
    }

    add(_oftenListened().map((_Play e) => e.track));
    final qi = _quickIndex();
    if (qi >= 0) add(_tracksOf(_sections[qi]));
    if (out.isEmpty) add(_recent);
    return out;
  }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_recentKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((dynamic e) => YtTrack.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  void _onNow() {
    final t = _player.now.value;
    _listenTimer?.cancel();
    if (t == null) return;
    // one listen = the song is still playing after [_listenSeconds] seconds (a quick skip does not count)
    _listenTimer = Timer(const Duration(seconds: _listenSeconds), () {
      if (_player.now.value?.id == t.id && _player.player.playing) _countListen(t);
    });
    final next = <YtTrack>[t, ..._recent.where((YtTrack x) => x.id != t.id)].take(40).toList();
    if (mounted) setState(() => _recent = next);
    unawaited(_saveRecent(next));
  }

  Future<void> _saveRecent(List<YtTrack> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_recentKey, jsonEncode(list.map((YtTrack e) => e.toJson()).toList()));
    } catch (_) {}
  }

  // ------------------------------------------------------------------ Search Logic

  Future<void> _runSearch([String? q]) async {
    if (q != null) _controller.text = q;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _searched = false);
      return;
    }
    final mode = _mode;
    FocusScope.of(context).unfocus();
    setState(() {
      _suggClear();
      _loading = true;
      _searched = true;
      _error = null;
    });
    try {
      final r = await YtMusicService().search(text, songs: mode == 0);
      _cache[mode] = r;
      _cacheQ[mode] = text;
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _suggClear() {
    _suggTimer?.cancel();
    _suggGen++;
    _sugg = <String>[];
    _suggTracks = <YtTrack>[];
  }

  void _onType(String v) {
    setState(() {});
    _suggTimer?.cancel();
    final q = v.trim();
    if (q.isEmpty || _mode >= 2) {
      setState(_suggClear);
      return;
    }
    final gen = ++_suggGen;
    _suggTimer = Timer(const Duration(milliseconds: 280), () => _fetchSuggest(q, gen));
  }

  Future<void> _fetchSuggest(String q, int gen) async {
    if (await YtMusicService.isOffline()) return;
    var texts = <String>[];
    var tracks = <YtTrack>[];
    await Future.wait(<Future<void>>[
      () async {
        try {
          final r = await (_ytMusic as dynamic).getSearchSuggestions(q);
          if (r is List) texts = <String>[for (final e in r) if (e is String && e.trim().isNotEmpty) e.trim()];
        } catch (_) {}
      }(),
      () async {
        try {
          tracks = await YtMusicService().search(q, songs: true);
        } catch (_) {}
      }(),
    ]);
    if (!mounted || gen != _suggGen) return;
    setState(() {
      _sugg = texts.take(5).toList();
      _suggTracks = tracks.take(4).toList();
    });
  }

  bool get _suggVisible => _searchFocus && _controller.text.trim().isNotEmpty && _mode < 2 && (_sugg.isNotEmpty || _suggTracks.isNotEmpty);

  Widget _hl(String s, String typed) {
    final dim = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: Colors.white.withAlpha(150));
    const bold = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800);
    if (typed.isNotEmpty && s.toLowerCase().startsWith(typed.toLowerCase())) {
      return Text.rich(TextSpan(children: <TextSpan>[TextSpan(text: s.substring(0, typed.length), style: dim), TextSpan(text: s.substring(typed.length), style: bold)]), maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: bold);
  }

  Widget _suggestPanel() {
    final q = _controller.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: glass(radius: 22),
        clipBehavior: Clip.antiAlias,
        child: Column(children: <Widget>[
          for (final s in _sugg)
            InkWell(
              onTap: () => _runSearch(s),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                child: Row(children: <Widget>[
                  Icon(Icons.search_rounded, size: 20, color: Colors.white.withAlpha(120)),
                  const SizedBox(width: 14),
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: _hl(s, q))),
                  IconButton(
                    tooltip: 'Use this text',
                    icon: Icon(Icons.north_west_rounded, size: 18, color: Colors.white.withAlpha(110)),
                    onPressed: () {
                      _controller.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
                      _onType(s);
                    },
                  ),
                ]),
              ),
            ),
          if (_sugg.isNotEmpty && _suggTracks.isNotEmpty) Divider(height: 1, color: Colors.white.withAlpha(18)),
          for (final t in _suggTracks)
            InkWell(
              onTap: () {
                FocusScope.of(context).unfocus();
                setState(_suggClear);
                _play(t);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(children: <Widget>[
                  _cover(t.thumbnail ?? 'https://i.ytimg.com/vi/${t.id}/hqdefault.jpg', 44, radius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text('Song · ${t.artist}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(135))),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  void _setMode(int m) {
    if (m == _mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _mode = m;
      _error = null;
      _searched = _controller.text.trim().isNotEmpty && m < 2;
    });
    if (m == 2) _openList = null;
    if (m < 2 && _controller.text.trim().isNotEmpty) {
      _runSearch();
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

  // ------------------------------------------------------------------ UI Components

  Widget _header() {
    final back = _mode == 2 && _openList != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (back)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => setState(() => _openList = null)),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_greeting().toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 3.3, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(128))),
            const SizedBox(height: 4),
            GradText('Discover', accent: _accent, size: 38),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: darkPill(),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.smart_display_rounded, color: Color(0xFFFF5252), size: 20),
            SizedBox(width: 7),
            Text('YouTube', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }

  Widget _searchBox() {
    final deco = glass(radius: 24).copyWith(
      border: Border.all(color: _searchFocus ? lighter(_accent).withAlpha(150) : Colors.white.withAlpha(26)),
      boxShadow: _searchFocus ? [BoxShadow(color: _accent.withAlpha(90), blurRadius: 28, spreadRadius: -8)] : null,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: deco,
        child: Focus(
          onFocusChange: (bool f) => setState(() => _searchFocus = f),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 16),
            cursorColor: lighter(_accent),
            onChanged: _onType,
            onSubmitted: (_) => _runSearch(),
            decoration: InputDecoration(
              hintText: _mode == 0 ? 'Songs, artists, albums' : (_mode == 1 ? 'Search videos' : ''),
              hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
              prefixIcon: Icon(Icons.search_rounded, color: _searchFocus ? lighter(_accent) : Colors.white.withAlpha(140)),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        setState(() {
                          _searched = false;
                          _suggClear();
                        });
                      },
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 17),
            ),
          ),
        ),
      ),
    );
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
              boxShadow: on ? [BoxShadow(color: _accent.withAlpha(120), blurRadius: 20, offset: const Offset(0, 6), spreadRadius: -6)] : null,
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
        decoration: glass(radius: 999),
        child: Row(children: [
          item(0, Icons.music_note_rounded, 'Songs'),
          item(1, Icons.smart_display_rounded, 'Videos'),
          item(2, Icons.queue_music_rounded, 'Lists'),
        ]),
      ),
    );
  }

  Widget _row(YtTrack t) {
    final opening = _opening == t.id;
    final isPlaying = _player.current?.id == t.id;
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
                _cover(t.thumbnail ?? '', 54, radius: 12),
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
                  Text('', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(120))),

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

  // ------------------------------------------------------------------ Home Feed Elements

  List<Widget> _homeFeed() {
    final quickIdx = _quickIndex();
    final quick = _quickList();

    final out = <Widget>[_moodChips()];
    if (_isLoading && _sections.isEmpty && quick.isNotEmpty) {
      // the feed is still loading: show the saved Quick picks at once
      out.add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_quickHeader(quick), _quickPicks(quick)]));
      out.add(Padding(padding: const EdgeInsets.only(top: 30), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: lighter(_accent))))));
    } else if (_isLoading && _sections.isEmpty) {
      out.add(Padding(padding: const EdgeInsets.only(top: 110), child: Center(child: CircularProgressIndicator(color: lighter(_accent)))));
    } else if (_failed && _sections.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
        child: Column(children: <Widget>[
          Icon(Icons.cloud_off_rounded, size: 52, color: Colors.white.withAlpha(110)),
          const SizedBox(height: 14),
          Text(_offline ? 'Offline mode is on' : 'Could not load YouTube Music', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_offline ? 'Turn it off in Settings → Privacy & online to use YouTube Music.' : 'Check the internet connection and try again.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(140))),
          const SizedBox(height: 20),
          Cta(label: 'Try again', icon: Icons.refresh_rounded, accent: _accent, onTap: () {
            setState(() => _isLoading = true);
            _loadHomeFeed();
          }),
        ]),
      ));
    } else {
      var n = 0;
      if (quick.isNotEmpty) {
        out.add(Reveal(index: n++, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_quickHeader(quick), _quickPicks(quick)])));
      }
      if (_hasKeepListening()) out.add(Reveal(index: n++, child: _keepListening()));
      for (var i = 0; i < _sections.length; i++) {
        if (i == quickIdx) continue;
        final s = _sections[i];
        if (s.contents.isEmpty) continue;
        final idx = n < 6 ? n++ : 6;
        out.add(Reveal(
          index: idx,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _title(s.title.toLowerCase() == 'listen again' ? 'Keep listening' : s.title),
            _cardsRow(s),
          ]),
        ));
      }
    }
    return out;
  }

  Widget _moodChips() => SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          itemCount: _moods.length,
          separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 10),
          itemBuilder: (BuildContext context, int i) {
            final m = _moods[i];
            return Material(
              color: Colors.transparent,
              child: Ink(
                decoration: glass(radius: 999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _setMode(0);
                    _controller.text = '${m.label} songs';
                    _runSearch();
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 6, 16, 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(m.color), m.color]),
                          boxShadow: [BoxShadow(color: m.color.withAlpha(110), blurRadius: 12, spreadRadius: -4)],
                        ),
                        child: Icon(m.icon, size: 17, color: const Color(0xFF0B0B10)),
                      ),
                      const SizedBox(width: 9),
                      Text(m.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 14),
        child: Row(children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [lighter(_accent), _accent]),
              boxShadow: [BoxShadow(color: _accent.withAlpha(140), blurRadius: 10, spreadRadius: -2)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
        ]),
      );

  /// "Quick picks" with Play all and two arrows to flip between the pages.
  Widget _quickHeader(List<YtTrack> tracks) {
    final pages = (tracks.length / _quickRows).ceil();
    Widget arrow(IconData icon, bool enabled, VoidCallback go) => Material(
          color: Colors.transparent,
          child: Ink(
            width: 36,
            height: 36,
            decoration: darkPill(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? go : null,
              child: Icon(icon, size: 20, color: Colors.white.withAlpha(enabled ? 220 : 70)),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 14, 12),
      child: Row(children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [lighter(_accent), _accent]),
            boxShadow: [BoxShadow(color: _accent.withAlpha(140), blurRadius: 10, spreadRadius: -2)],
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Text('Quick picks', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
        Cta(label: 'Play all', icon: Icons.play_arrow_rounded, accent: _accent, ghost: true, compact: true, onTap: () => _player.playFrom(tracks, 0)),
        if (pages > 1) ...[
          const SizedBox(width: 8),
          arrow(Icons.chevron_left_rounded, _quickPage > 0, () => _quickCtl.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic)),
          const SizedBox(width: 6),
          arrow(Icons.chevron_right_rounded, _quickPage < pages - 1, () => _quickCtl.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic)),
        ],
      ]),
    );
  }

  /// Pages of four songs that you swipe sideways (up to 12 songs, so up to 3 pages), with dots below.
  Widget _quickPicks(List<YtTrack> tracks) {
    final pages = (tracks.length / _quickRows).ceil();
    final rows = tracks.length < _quickRows ? tracks.length : _quickRows;
    return Column(children: [
      SizedBox(
        height: rows * 70.0 + (rows - 1) + 2, // rows, the thin dividers between them, and a little air
        child: ValueListenableBuilder<YtTrack?>(
          valueListenable: _player.now,
          builder: (BuildContext context, YtTrack? playing, Widget? _) => PageView.builder(
            controller: _quickCtl,
            padEnds: false,
            itemCount: pages,
            onPageChanged: (int p) => setState(() => _quickPage = p),
            itemBuilder: (BuildContext context, int page) {
              final from = page * _quickRows;
              final to = from + _quickRows > tracks.length ? tracks.length : from + _quickRows;
              return Padding(
                padding: EdgeInsets.fromLTRB(page == 0 ? 16 : 6, 0, page == pages - 1 ? 16 : 6, 0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Material(
                      color: Colors.transparent,
                      child: Ink(
                        decoration: glass(radius: 26),
                        child: Column(children: <Widget>[
                          for (var i = from; i < to; i++) ...[
                            if (i > from) Divider(height: 1, indent: 78, endIndent: 14, color: Colors.white.withAlpha(16)),
                            _songRow(tracks, i, playing?.id == tracks[i].id),
                          ],
                        ]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      if (pages > 1)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < pages; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _quickPage ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _quickPage ? lighter(_accent) : Colors.white.withAlpha(50),
                ),
              ),
          ]),
        ),
    ]);
  }

  Widget _songRow(List<YtTrack> tracks, int index, bool on) {
    final t = tracks[index];
    return SizedBox(
      height: 70,
      child: InkWell(
        onTap: () => _player.playFrom(tracks, index),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(children: <Widget>[
            _cover(t.thumbnail ?? '', 52, radius: 14),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: on ? lighter(_accent) : null)),
                const SizedBox(height: 2),
                Text(
                  (_plays[t.id]?.count ?? 0) >= _oftenMin ? '${t.artist} · ${_plays[t.id]!.count} plays' : t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(140)),
                ),
              ]),
            ),
            if (on) Padding(padding: const EdgeInsets.only(right: 6), child: EqBars(playing: true, color: lighter(_accent), height: 16)),
            IconButton(tooltip: 'Add to a playlist', icon: Icon(Icons.playlist_add_rounded, color: Colors.white.withAlpha(170)), onPressed: () => showAddToPlaylist(context, t, _accent)),
          ]),
        ),
      ),
    );
  }

  List<YtTrack> _keepArtists() {
    final seen = <String>{};
    final artists = <YtTrack>[];
    for (final t in _recent) {
      final a = t.artist.trim();
      if (a.isEmpty || a == 'YouTube Video' || a == 'Unknown Artist') continue;
      if (seen.add(a.toLowerCase())) artists.add(t);
      if (artists.length >= 12) break;
    }
    return artists;
  }

  bool _hasKeepListening() => _keepArtists().isNotEmpty;

  /// Round pictures with a glowing ring: the artists played lately.
  Widget _keepListening() {
    final artists = _keepArtists();
    if (artists.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      _title('Keep listening'),
      SizedBox(
        height: 190,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: artists.length,
          itemBuilder: (BuildContext context, int i) {
            final t = artists[i];
            return GestureDetector(
              onTap: () {
                _openPage(t.artist, 'Artist', t.thumbnail ?? '', () async {
                  final r = await YtMusicService().search(t.artist, songs: true);
                  return _Loaded(r, false);
                });
              },
              child: Container(
                width: 128,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(_accent), _accent, darker(_accent, 0.3)]),
                      boxShadow: [BoxShadow(color: _accent.withAlpha(110), blurRadius: 24, offset: const Offset(0, 10), spreadRadius: -8)],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: kBg),
                      child: _cover(t.thumbnail ?? '', 110, circle: true),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text('ARTIST', style: TextStyle(fontSize: 9.5, letterSpacing: 2.4, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(100))),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _cardsRow(HomeSection s) {
    final round = s.contents.where((dynamic c) => c is ArtistDetailed).length * 2 > s.contents.length;
    return SizedBox(
      height: round ? 196 : 230,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: s.contents.length,
        itemBuilder: (BuildContext context, int i) => _card(s.contents[i]),
      ),
    );
  }

  Widget _card(dynamic item) {
    var title = _nameOf(item);
    var subtitle = '';
    if (item is SongDetailed) {
      subtitle = item.artist.name;
    } else if (item is VideoDetailed) {
      subtitle = 'VIDEO';
    } else if (item is PlaylistDetailed) {
      subtitle = 'PLAYLIST';
    } else if (item is AlbumDetailed) {
      subtitle = 'ALBUM';
    } else if (item is ArtistDetailed) {
      subtitle = 'ARTIST';
    }
    if (title.isEmpty) title = 'Unknown';
    const size = 150.0;
    final isArtist = item is ArtistDetailed;
    final songLike = item is SongDetailed;
    return GestureDetector(
      onTap: () => _playItem(item),
      child: Container(
        width: size,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(crossAxisAlignment: isArtist ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: <Widget>[
          Stack(children: [
            Container(
              decoration: BoxDecoration(
                shape: isArtist ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isArtist ? null : BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 20, offset: const Offset(0, 12), spreadRadius: -8)],
              ),
              foregroundDecoration: BoxDecoration(
                shape: isArtist ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isArtist ? null : BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withAlpha(30)),
              ),
              child: _cover(_thumbOf(item), size, radius: 22, circle: isArtist),
            ),
            if (!isArtist)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(_accent), _accent]),
                    boxShadow: [BoxShadow(color: _accent.withAlpha(150), blurRadius: 14, spreadRadius: -3)],
                  ),
                  child: Icon(songLike ? Icons.play_arrow_rounded : Icons.arrow_forward_rounded, size: 20, color: const Color(0xFF0B0B10)),
                ),
              ),
          ]),
          const SizedBox(height: 11),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: isArtist ? TextAlign.center : TextAlign.start, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 3),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: songLike ? 12.5 : 9.5, letterSpacing: songLike ? 0 : 2.2, fontWeight: songLike ? FontWeight.w400 : FontWeight.w700, color: Colors.white.withAlpha(songLike ? 150 : 105))),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ Feed utilities
  String _nameOf(dynamic item) { try { return (item.name as String?) ?? ''; } catch (_) { return ''; } }
  String _thumbOf(dynamic item) { try { final list = item.thumbnails as List<dynamic>; if (list.isEmpty) return ''; return (list.last.url as String?) ?? ''; } catch (_) { return ''; } }

  YtTrack? _toTrack(dynamic item) {
    if (item is SongDetailed) {
      return YtTrack(id: item.videoId, title: item.name, artist: item.artist.name, thumbnail: _hi(_thumbOf(item)), duration: Duration(seconds: item.duration ?? 0));
    }
    if (item is VideoDetailed) {
      return YtTrack(id: item.videoId, title: item.name, artist: 'YouTube Video', thumbnail: _hi(_thumbOf(item)), duration: Duration.zero);
    }
    return null;
  }

  List<YtTrack> _tracksOf(HomeSection s) { final out = <YtTrack>[]; for (final dynamic c in s.contents) { final t = _toTrack(c); if (t != null && t.id.isNotEmpty) out.add(t); } return out; }
  int _quickIndex() { for (var i = 0; i < _sections.length; i++) { if (_sections[i].title.toLowerCase().contains('quick') && _tracksOf(_sections[i]).isNotEmpty) return i; } for (var i = 0; i < _sections.length; i++) { if (_tracksOf(_sections[i]).length >= 4) return i; } return -1; }

  Future<void> _playItem(dynamic item) async {
    if (item is SongDetailed || item is VideoDetailed) {
      final t = _toTrack(item);
      if (t != null) await _player.play(t);
    } else if (item is PlaylistDetailed) {
      _openPage(item.name, 'Playlist', _thumbOf(item), () => _loadPlaylist(item));
    } else if (item is AlbumDetailed) {
      _openPage(_nameOf(item), 'Album', _thumbOf(item), () => _loadAlbum(item));
    } else if (item is ArtistDetailed) {
      _openPage(_nameOf(item), 'Artist', _thumbOf(item), () => _loadArtist(item));
    }
  }

  void _openPage(String title, String kind, String cover, Future<_Loaded> Function() load) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => _ListPage(title: title, kind: kind, cover: cover, accent: _accent, load: load)));
  }

  Future<_Loaded> _loadPlaylist(PlaylistDetailed item) async {
    final browseId = item.playlistId.startsWith('VL') ? item.playlistId : 'VL${item.playlistId}';
    try {
      final videos = await _ytMusic.getPlaylistVideos(browseId);
      final tracks = videos.where((v) => v.videoId.isNotEmpty).map((v) => YtTrack(id: v.videoId, title: v.name, artist: 'YouTube Video', thumbnail: _hi(_thumbOf(v)), duration: Duration.zero)).toList();
      if (tracks.isNotEmpty) return _Loaded(tracks, false);
    } catch (e) { debugPrint('Error: $e'); }
    return _Loaded(await YtMusicService().search(item.name, songs: true), true);
  }

  Future<_Loaded> _loadAlbum(AlbumDetailed item) async {
    final cover = _hi(_thumbOf(item));
    try {
      final dynamic a = await (_ytMusic as dynamic).getAlbum((item as dynamic).albumId);
      final out = <YtTrack>[];
      for (final dynamic s in (a.songs as List<dynamic>)) { final t = _toTrack(s); if (t != null && t.id.isNotEmpty) out.add((t.thumbnail ?? '').isEmpty ? YtTrack(id: t.id, title: t.title, artist: t.artist, thumbnail: cover, duration: t.duration) : t); }
      if (out.isNotEmpty) return _Loaded(out, false);
    } catch (e) { debugPrint('Error: $e'); }
    return _Loaded(await YtMusicService().search(_nameOf(item), songs: true), true);
  }

  Future<_Loaded> _loadArtist(ArtistDetailed item) async {
    try {
      final dynamic a = await (_ytMusic as dynamic).getArtist((item as dynamic).artistId);
      final out = <YtTrack>[];
      for (final dynamic s in (a.topSongs as List<dynamic>)) { final t = _toTrack(s); if (t != null && t.id.isNotEmpty) out.add(t); }
      if (out.isNotEmpty) return _Loaded(out, false);
    } catch (e) { debugPrint('Error: $e'); }
    return _Loaded(await YtMusicService().search(_nameOf(item), songs: true), false);
  }

  // ------------------------------------------------------------------ Search Views

  Widget _results_() {
    final results = _mode == 2 ? const <YtTrack>[] : _cache[_mode];
    if (_loading && results.isEmpty) return const Center(child: CircularProgressIndicator());
    if (results.isEmpty) return const Center(child: Text('No results found', style: TextStyle(color: Colors.white54)));
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: results.length,
      itemBuilder: (_, int i) => _row(results[i]),
    );
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
                    Container(width: 44, height: 44, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(_accent), _accent])), child: const Icon(Icons.add_rounded, color: Color(0xFF0B0B10))),
                    const SizedBox(width: 14),
                    const Text('New playlist', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
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
                        p.tracks.isEmpty ? Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white.withAlpha(16), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.queue_music_rounded, color: Colors.white.withAlpha(120))) : _cover(p.tracks.first.thumbnail ?? '', 56),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          Text('${p.tracks.length} songs', style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(130))),
                        ])),
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
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      Row(children: [
        Expanded(child: Text(p.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await YtPlaylists.shared.delete(p.id); if (mounted) setState(() => _openList = null); }),
      ]),
      const SizedBox(height: 10),
      for (var i = 0; i < p.tracks.length; i++)
        _row(p.tracks[i]),
    ]);
  }

  // ------------------------------------------------------------------ Page Build

  @override
  Widget build(BuildContext context) {
    // The background (glows, dots, wallpaper) comes from the app shell, so this page stays see-through.
    final Widget content;
    final typing = _suggVisible;
    if (typing && _searched) {
      content = Column(children: [
        _header(),
        _searchBox(),
        Expanded(child: SingleChildScrollView(child: _suggestPanel())),
      ]);
    } else if (typing) {
      content = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [_header(), _searchBox(), _suggestPanel()],
      );
    } else if (_mode == 2 || _searched) {
      content = Column(children: [
        _header(),
        _searchBox(),
        _modeBar(),
        if (_loading && _searched) LinearProgressIndicator(minHeight: 2, color: _accent, backgroundColor: Colors.transparent),
        Expanded(child: _mode == 2 ? _playlistsView() : _results_()),
      ]);
    } else {
      content = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [_header(), _searchBox(), _modeBar(), ..._homeFeed()],
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(children: [
          Expanded(child: content),
          _HomeMini(accent: _accent, cover: _cover),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Helpers (Mini Player, Images, List Page)

/// Turns its child slowly while [spinning] is true, like the cover in the main player's mini bar.
/// It stops (and keeps its angle) when paused, and stays still when "calm" is on.
class _Spin extends StatefulWidget {
  final bool spinning;
  final Widget child;
  const _Spin({required this.spinning, required this.child});
  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  void _sync() {
    if (widget.spinning && !kLook.value.calm) {
      if (!_c.isAnimating) _c.repeat();
    } else if (_c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    kLook.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Spin old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    kLook.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: RotationTransition(turns: _c, child: widget.child));
}

class _HomeMini extends StatelessWidget {
  final Color accent;
  final Widget Function(String url, double size, {double radius, bool circle}) cover;
  const _HomeMini({required this.accent, required this.cover});

  @override
  Widget build(BuildContext context) {
    final ap = AthanaPlayer.shared;
    return ValueListenableBuilder<YtTrack?>(
      valueListenable: ap.now,
      builder: (BuildContext context, YtTrack? t, Widget? _) {
        if (t == null) return const SizedBox.shrink();
        final p = ap.player;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: StreamBuilder<PlayerState>(
            stream: p.playerStateStream,
            builder: (BuildContext context, AsyncSnapshot<PlayerState> snap) {
              final st = snap.data;
              final busy = st != null && (st.processingState == ProcessingState.loading || st.processingState == ProcessingState.buffering);
              final on = st?.playing ?? false;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: accent.withAlpha(70), blurRadius: 30, offset: const Offset(0, 10), spreadRadius: -10), BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 22, offset: const Offset(0, 8), spreadRadius: -8)],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: glass(radius: 30).copyWith(color: const Color(0xF2181520)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (BuildContext _) => YtNowPlaying(player: ap, track: t, accent: accent))),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
                        child: Row(children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(accent), accent])),
                            child: _Spin(spinning: on, child: cover(t.thumbnail ?? 'https://i.ytimg.com/vi/${t.id}/hqdefault.jpg', 44, circle: true)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                              const SizedBox(height: 2),
                              Text(busy ? 'LOADING…' : t.artist.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(125))),
                            ]),
                          ),
                          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.skip_previous_rounded), onPressed: () => ap.previous()),
                          StreamBuilder<Duration>(
                            stream: p.positionStream,
                            builder: (BuildContext context, AsyncSnapshot<Duration> ps) {
                              final pos = ps.data ?? Duration.zero;
                              final dur = p.duration ?? t.duration;
                              final v = dur.inMilliseconds <= 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0).toDouble();
                              return SizedBox(
                                width: 52,
                                height: 52,
                                child: Stack(alignment: Alignment.center, children: [
                                  SizedBox(width: 52, height: 52, child: CircularProgressIndicator(value: v, strokeWidth: 2.6, color: lighter(accent), backgroundColor: Colors.white.withAlpha(28))),
                                  Material(
                                    color: Colors.transparent,
                                    child: Ink(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighter(accent), accent]),
                                        boxShadow: [BoxShadow(color: accent.withAlpha(140), blurRadius: 16, spreadRadius: -4)],
                                      ),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: busy ? null : () => on ? ap.pause() : ap.resume(),
                                        child: busy
                                            ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0B0B10)))
                                            : Icon(on ? Icons.pause_rounded : Icons.play_arrow_rounded, color: const Color(0xFF0B0B10), size: 26),
                                      ),
                                    ),
                                  ),
                                ]),
                              );
                            },
                          ),
                          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.skip_next_rounded), onPressed: () => ap.next()),
                        ]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

String _hi(String url, [int px = 544]) {
  if (url.isEmpty) return url;
  return url.replaceAllMapped(RegExp(r'=w\d+-h\d+[^/?&]*$'), (Match m) => '=w$px-h$px-l90-rj').replaceAllMapped(RegExp(r'=s\d+[^/?&]*$'), (Match m) => '=s$px');
}

Widget _cover(String url, double size, {double radius = 12, bool circle = false}) {
  final big = _hi(url);
  Widget holder() => Container(width: size, height: size, color: Colors.white.withAlpha(20), child: Icon(Icons.music_note_rounded, color: Colors.white.withAlpha(110), size: size * 0.32));
  Widget pic = url.isEmpty ? holder() : Image.network(big, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (BuildContext _, Object __, StackTrace? ___) => big == url ? holder() : Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (BuildContext _, Object __, StackTrace? ___) => holder()));
  return circle ? ClipOval(child: pic) : ClipRRect(borderRadius: BorderRadius.circular(radius), child: pic);
}

class _Loaded {
  final List<YtTrack> tracks;
  final bool approximate;
  const _Loaded(this.tracks, this.approximate);
}

String _mmss(Duration d) { if (d.inSeconds <= 0) return ''; final m = d.inMinutes; final sec = (d.inSeconds % 60).toString().padLeft(2, '0'); return '$m:$sec'; }

class _ListPage extends StatefulWidget {
  final String title;
  final String kind;
  final String cover;
  final Color accent;
  final Future<_Loaded> Function() load;
  const _ListPage({required this.title, required this.kind, required this.cover, required this.accent, required this.load});
  @override
  State<_ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<_ListPage> {
  bool _loading = true;
  Object? _error;
  _Loaded _data = const _Loaded(<YtTrack>[], false);

  @override
  void initState() { super.initState(); _go(); }

  Future<void> _go() async {
    setState(() { _loading = true; _error = null; });
    try { final d = await widget.load(); if (mounted) setState(() { _data = d; _loading = false; }); }
    catch (e) { if (mounted) setState(() { _error = e; _loading = false; }); }
  }

  String get _pic => widget.cover.isNotEmpty ? widget.cover : (_data.tracks.isEmpty ? '' : (_data.tracks.first.thumbnail ?? ''));

  @override
  Widget build(BuildContext context) {
    final tracks = _data.tracks;
    final accent = widget.accent;
    final round = widget.kind == 'Artist';
    final kids = <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
          child: Container(
            decoration: darkPill(),
            child: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop()),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Center(
        child: Container(
          decoration: BoxDecoration(
            shape: round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: round ? null : BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: accent.withAlpha(120), blurRadius: 56, offset: const Offset(0, 24), spreadRadius: -12)],
          ),
          child: _cover(_pic, 200, radius: 30, circle: round),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Text(widget.kind.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, letterSpacing: 3.2, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(128))),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
        child: Text(widget.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.9, height: 1.1)),
      ),
      if (!_loading && tracks.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            InfoChip(icon: Icons.music_note_rounded, label: '${tracks.length} songs'),
            if (_data.approximate) const InfoChip(icon: Icons.auto_awesome_rounded, label: 'Songs that match'),
          ]),
        ),
    ];

    if (_loading) {
      kids.add(Padding(padding: const EdgeInsets.only(top: 50), child: Center(child: CircularProgressIndicator(color: lighter(accent)))));
    } else if (_error != null || tracks.isEmpty) {
      kids.add(Padding(
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 0),
        child: Column(children: <Widget>[
          Icon(Icons.music_off_rounded, size: 46, color: Colors.white.withAlpha(110)),
          const SizedBox(height: 12),
          Text(_error != null ? 'Could not open this list' : 'No songs found', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          Cta(label: 'Try again', icon: Icons.refresh_rounded, accent: accent, onTap: _go),
        ]),
      ));
    } else {
      kids.add(Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
        child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
          Cta(label: 'Play', icon: Icons.play_arrow_rounded, accent: accent, onTap: () => AthanaPlayer.shared.playFrom(tracks, 0)),
          Cta(label: 'Shuffle', icon: Icons.shuffle_rounded, accent: accent, ghost: true, onTap: () => AthanaPlayer.shared.playFrom(tracks, 0, shuffle: true)),
        ]),
      ));
      kids.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: glass(radius: 26),
              child: ValueListenableBuilder<YtTrack?>(
                valueListenable: AthanaPlayer.shared.now,
                builder: (BuildContext context, YtTrack? playing, Widget? _) => Column(children: <Widget>[
                  for (var i = 0; i < tracks.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 82, endIndent: 14, color: Colors.white.withAlpha(16)),
                    _row(tracks, i, playing?.id == tracks[i].id),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ));
    }

    return Scaffold(
      backgroundColor: kBg,
      body: Backdrop(
        accent: accent,
        child: SafeArea(
          child: Column(children: <Widget>[
            Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 14), children: kids)),
            _HomeMini(accent: accent, cover: _cover),
          ]),
        ),
      ),
    );
  }

  Widget _row(List<YtTrack> tracks, int i, bool on) {
    final t = tracks[i];
    final len = _mmss(t.duration);
    return InkWell(
      onTap: () => AthanaPlayer.shared.playFrom(tracks, i),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: <Widget>[
          _cover(t.thumbnail ?? 'https://i.ytimg.com/vi/${t.id}/hqdefault.jpg', 52, radius: 14),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: on ? lighter(widget.accent) : null)),
            const SizedBox(height: 2),
            Text(len.isEmpty ? t.artist : '${t.artist} · $len', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(140))),
          ])),
          if (on) Padding(padding: const EdgeInsets.only(right: 6), child: EqBars(playing: true, color: lighter(widget.accent), height: 16)),
          IconButton(tooltip: 'Add to a playlist', icon: Icon(Icons.playlist_add_rounded, color: Colors.white.withAlpha(170)), onPressed: () => showAddToPlaylist(context, t, widget.accent)),
        ]),
      ),
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
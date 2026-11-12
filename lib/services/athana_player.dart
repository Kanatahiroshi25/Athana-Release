import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/yt_track.dart';
import 'yt_music_service.dart';
import '../app_state.dart';

class AthanaPlayer {
  AthanaPlayer({YtMusicService? service}) : _service = service ?? YtMusicService() {
    _player.processingStateStream.listen((ProcessingState s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
  }

  static final AthanaPlayer shared = AthanaPlayer();

  final YtMusicService _service;
  final AudioPlayer _player = AudioPlayer();
  final math.Random _rng = math.Random();

  AudioPlayer get player => _player;
  YtTrack? _current;
  YtTrack? get current => _current;

  final ValueNotifier<YtTrack?> now = ValueNotifier<YtTrack?>(null);
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  // 👇 NEW DATA WARNING NOTIFIER 👇
  final ValueNotifier<YtTrack?> askForData = ValueNotifier<YtTrack?>(null);
  bool _bypassDataCheck = false;
  // 👆 ------------------------ 👆

  bool autoplay = true;

  final List<YtTrack> _history = <YtTrack>[];
  final List<YtTrack> _queue = <YtTrack>[];
  final Set<String> _seen = <String>{};
  Future<void>? _fillFuture;
  bool _fixed = false;
  String? _endFor;

  YtTrack? get upNext => _queue.isEmpty ? null : _queue.first;
  bool get finding => _fillFuture != null;
  List<YtTrack> get queue => List.unmodifiable(_queue);

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      tick.value++;
    }
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final selected = _queue[index];
    _queue.removeRange(0, index + 1);
    tick.value++;
    await play(selected, keepQueue: true);
  }

  void forceAutoplayFill() {
    if (autoplay) unawaited(_fillQueue(force: true));
  }

  /// Streams the song from YouTube. Nothing is saved on the phone. The data settings (Wi-Fi only, ask before using
  /// mobile data) are respected unless the person has just said yes for this song.
  Future<void> _loadAndPlay(YtTrack track) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final prefs = Prefs();
      final s = sp.getString('athana_set');
      if (s != null) prefs.load(Map<String, dynamic>.from(jsonDecode(s) as Map));

      if (!_bypassDataCheck) {
        final connectivityResult = await Connectivity().checkConnectivity();
        final isMobile = connectivityResult.contains(ConnectivityResult.mobile);

        if (isMobile) {
          if (prefs.networkMode == 2) {
            throw Exception('Wi-Fi only mode is enabled in Settings. Please connect to Wi-Fi.');
          } else if (prefs.networkMode == 1) {
            askForData.value = track;
            throw Exception('WAITING_FOR_DATA_PERMISSION');
          }
        }
      }

      final url = await _service.getAudioUrl(track.id, dataUsage: prefs.dataUsage);
      await _player.setUrl(url);
    } catch (e) {
      if (e.toString().contains('WAITING_FOR_DATA_PERMISSION')) {
        // Ignore this specific error, the UI will handle it
      } else {
        rethrow;
      }
    }
  }

  Future<void> play(YtTrack track, {bool fromHistory = false, bool keepQueue = false, List<YtTrack>? thenQueue, bool bypassData = false}) async {
    _bypassDataCheck = bypassData;
    final prev = _current;
    if (prev != null && prev.id != track.id && !fromHistory) {
      _history.add(prev);
      if (_history.length > 50) _history.removeAt(0);
    }
    if (!keepQueue) {
      _queue.clear();
      _fixed = false;
      if (thenQueue != null) {
        _queue.addAll(thenQueue);
        _fixed = thenQueue.isNotEmpty;
      }
      tick.value++;
    }
    _current = track;
    now.value = track;
    _seen.add(track.id);
    if (_seen.length > 300) _seen.clear();
    _endFor = null;

    await _loadAndPlay(track);

    unawaited(_player.play());
    unawaited(_fillQueue());
  }

  Future<void> playFrom(List<YtTrack> tracks, int index, {bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    final list = List<YtTrack>.of(tracks);
    if (shuffle) {
      list.shuffle(_rng);
      await play(list.first, thenQueue: list.sublist(1));
    } else {
      final i = index.clamp(0, list.length - 1).toInt();
      await play(list[i], thenQueue: list.sublist(i + 1));
    }
  }

  Future<void> retry() async {
    if (_current == null) return;
    final pos = _player.position;
    await _loadAndPlay(_current!);
    await _player.seek(pos);
    unawaited(_player.play());
  }

  void _onCompleted() {
    final c = _current;
    if (c == null || _endFor == c.id) return;
    _endFor = c.id;
    if (autoplay) unawaited(next());
  }

  Future<bool> next() async {
    for (var tries = 0; tries < 4; tries++) {
      if (_queue.isEmpty) {
        _fixed = false;
        await _fillQueue(force: true);
      }
      if (_queue.isEmpty) return false;
      final t = _queue.removeAt(0);
      tick.value++;
      try {
        await play(t, keepQueue: true);
        return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> previous() async {
    if (_player.position.inSeconds > 3 || _history.isEmpty) {
      await _player.seek(Duration.zero);
      return;
    }
    final t = _history.removeLast();
    final cur = _current;
    if (cur != null) {
      _queue.insert(0, cur);
      tick.value++;
    }
    await play(t, fromHistory: true, keepQueue: true);
  }

  Future<void> _fillQueue({bool force = false}) {
    if (_fixed && _queue.isNotEmpty) return Future<void>.value();
    final running = _fillFuture;
    if (running != null) return running;

    if (!force && _queue.length >= 20) return Future<void>.value();

    final f = _doFill().whenComplete(() {
      _fillFuture = null;
      tick.value++;
    });
    _fillFuture = f;
    tick.value++;
    return f;
  }

  static String _cleanArtist(String a) {
    var s = a.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').replaceAll(RegExp(r'VEVO$', caseSensitive: false), '').trim();
    s = s.split(RegExp(r'\s*(,|&|\bfeat\.?\b|\bft\.?\b|\bx\b)\s*', caseSensitive: false)).first.trim();
    return RegExp(r'^unknown artist$', caseSensitive: false).hasMatch(s) ? '' : s;
  }

  static String _cleanTitle(String t) => t.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _titleSignature(String title) {
    var t = title.toLowerCase();
    t = t.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), '');
    t = t.replaceAll(RegExp(r'[^\w\s]'), ' ');
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    words.removeAll(['official', 'video', 'lyrics', 'lyric', 'audio', 'feat', 'ft', 'remix', 'version', 'music', 'hd', 'hq', 'visualizer', 'mv']);
    final list = words.toList()..sort();
    return list.join('');
  }

  static bool _isPureMusic(YtTrack t) {
    final title = t.title.toLowerCase();
    final artist = t.artist.toLowerCase();

    if (artist == 'various artists' || artist == 'unknown artist' || artist.isEmpty) return false;
    if (artist.contains('tiktok') || artist.contains('7clouds') || artist.contains('mixes') || artist.contains('playlist')) return false;

    final junkWords = [
      'remix', 'nightcore', 'slowed', 'reverb', 'cover', 'live', 'animatic',
      'radio mix', 'mashup', 'edit', 'instrumental', 'karaoke', 'dj', 'bootleg',
      'extended', 'tiktok', 'lyric', 'visualizer', 'm/v', 'mv', 'official video',
      'music video', 'compilation', 'megamix', 'vs.', ' vs '
    ];

    for (final w in junkWords) {
      if (title.contains(w)) return false;
    }

    if (t.duration.inSeconds < 90) return false;

    return true;
  }

  Future<void> _doFill() async {
    final c = _current;
    if (c == null) return;

    final artist = _cleanArtist(c.artist);
    final title = _cleanTitle(c.title);
    final pool = <YtTrack>[];

    final queries = <String>[
      if (artist.isNotEmpty) '$artist top tracks',
      if (artist.isNotEmpty) '$artist mix',
      if (artist.isNotEmpty) '$artist radio',
      if (artist.isNotEmpty) '$artist best of',
      if (artist.isNotEmpty) '$artist $title',
      'trending music mix',
    ];

    for (final q in queries) {
      try {
        final r = await _service.search(q, songs: true);
        pool.addAll(r);
      } catch (_) {}
      if (pool.length >= 80) break;
    }

    final artistCount = <String, int>{};
    artistCount[artist.toLowerCase()] = 1;

    final finalPool = <YtTrack>[];
    final seenIds = <String>{};
    final seenSignatures = <String>{};

    for (final t in pool) {
      if (t.id == c.id || _seen.contains(t.id) || _queue.any((x) => x.id == t.id)) continue;
      if (seenIds.contains(t.id)) continue;
      if (t.duration.inSeconds < 90 || t.duration.inSeconds > 15 * 60) continue;

      if (!_isPureMusic(t)) continue;

      final sig = _titleSignature(t.title);
      if (seenSignatures.contains(sig)) continue;

      final trackArtist = _cleanArtist(t.artist).toLowerCase();
      final count = artistCount[trackArtist] ?? 0;
      if (count >= 2) continue;

      finalPool.add(t);
      seenIds.add(t.id);
      seenSignatures.add(sig);
      artistCount[trackArtist] = count + 1;

      if (finalPool.length >= 20) break;
    }

    finalPool.shuffle(_rng);

    final needed = 20 - _queue.length;
    if (needed > 0) {
      _queue.addAll(finalPool.take(needed));
    }
  }

  Timer? _sleepTimer;
  int sleepMinutes = 0;

  void setSleep(int minutes) {
    _sleepTimer?.cancel();
    sleepMinutes = minutes;
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        sleepMinutes = 0;
        autoplay = false;
        _player.pause();
      });
    }
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();
  Future<void> stop() => _player.stop();
  Future<void> dispose() => _player.dispose();
}
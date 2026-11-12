import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/yt_track.dart';

/// One playlist of YouTube songs. Only the song's name, artist, cover link and length are kept on the phone (a small list),
/// the sound itself is streamed when the song plays. Nothing is downloaded.
class YtPlaylist {
  final String id;
  String name;
  final List<YtTrack> tracks;
  YtPlaylist({required this.id, required this.name, required this.tracks});
}

/// The person's playlists, kept on this phone (in the app's settings storage) and shared by every screen.
class YtPlaylists extends ChangeNotifier {
  static final YtPlaylists shared = YtPlaylists();
  static const String _key = 'athana_yt_playlists';

  final List<YtPlaylist> lists = <YtPlaylist>[];
  Future<void>? _loading;

  /// Loads the saved playlists once (safe to call many times).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final out = <YtPlaylist>[];
        for (final e in (jsonDecode(raw) as List<dynamic>)) {
          final m = e as Map<String, dynamic>;
          final tracks = <YtTrack>[];
          for (final x in (m['tracks'] as List<dynamic>? ?? const <dynamic>[])) {
            final t = x as Map<String, dynamic>;
            tracks.add(YtTrack(
              id: (t['id'] ?? '').toString(),
              title: (t['title'] ?? '').toString(),
              artist: (t['artist'] ?? '').toString(),
              thumbnail: t['thumb'] as String?,
              duration: Duration(seconds: (t['dur'] as num?)?.toInt() ?? 0),
            ));
          }
          out.add(YtPlaylist(id: (m['id'] ?? '').toString(), name: (m['name'] ?? 'Playlist').toString(), tracks: tracks));
        }
        lists
          ..clear()
          ..addAll(out);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      final j = <Map<String, Object?>>[
        for (final p in lists)
          {
            'id': p.id,
            'name': p.name,
            'tracks': [
              for (final t in p.tracks) {'id': t.id, 'title': t.title, 'artist': t.artist, 'thumb': t.thumbnail, 'dur': t.duration.inSeconds},
            ],
          },
      ];
      await sp.setString(_key, jsonEncode(j));
    } catch (_) {}
  }

  YtPlaylist? byId(String id) {
    for (final p in lists) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool contains(String playlistId, String trackId) => byId(playlistId)?.tracks.any((t) => t.id == trackId) ?? false;

  /// true when the song is in at least one playlist.
  bool inAny(String trackId) => lists.any((p) => p.tracks.any((t) => t.id == trackId));

  Future<YtPlaylist> create(String name) async {
    await load();
    final n = name.trim().isEmpty ? 'My playlist' : name.trim();
    final p = YtPlaylist(id: DateTime.now().microsecondsSinceEpoch.toString(), name: n, tracks: <YtTrack>[]);
    lists.add(p);
    await _save();
    return p;
  }

  Future<void> rename(String id, String name) async {
    final p = byId(id);
    if (p == null || name.trim().isEmpty) return;
    p.name = name.trim();
    await _save();
  }

  Future<void> delete(String id) async {
    lists.removeWhere((p) => p.id == id);
    await _save();
  }

  /// Adds the song, or takes it out when it is already there. Returns true when it is in the playlist afterwards.
  Future<bool> toggle(String playlistId, YtTrack t) async {
    await load();
    final p = byId(playlistId);
    if (p == null) return false;
    final i = p.tracks.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      p.tracks.removeAt(i);
      await _save();
      return false;
    }
    p.tracks.add(t);
    await _save();
    return true;
  }

  Future<void> remove(String playlistId, String trackId) async {
    final p = byId(playlistId);
    if (p == null) return;
    p.tracks.removeWhere((t) => t.id == trackId);
    await _save();
  }
}

import 'dart:convert';

import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart' show Prefs;
import '../models/yt_track.dart';

const String kOfflineMessage = 'Offline mode is on (Settings → Privacy & online). Turn it off to use YouTube Music.';

class YtMusicService {
  /// True while Offline mode is switched on in Settings. Nothing from YouTube is fetched then.
  static Future<bool> isOffline() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString('athana_set');
      if (s == null) return false;
      final p = Prefs()..load(Map<String, dynamic>.from(jsonDecode(s) as Map));
      return p.offline;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requireOnline() async {
    if (await isOffline()) throw Exception(kOfflineMessage);
  }

  /// Search YouTube. [songs] true: only music (songs); false: ordinary videos.
  Future<List<YtTrack>> search(String query, {bool songs = false}) async {
    await requireOnline();
    if (!songs) return _run(query, SearchFilter.videos.value);
    try {
      final r = _songLike(await _run(query, 'music_songs'));
      if (r.isNotEmpty) return r;
    } catch (_) {}
    return _songLike(await _run(query, SearchFilter.videos.value));
  }

  List<YtTrack> _songLike(List<YtTrack> l) => l.where((t) => t.duration.inSeconds >= 30 && t.duration.inSeconds <= 12 * 60).toList();

  Future<List<YtTrack>> _run(String query, String filter) async {
    final page = await SearchExtractor.searchYoutube(query, [filter]);

    final out = <YtTrack>[];
    for (final v in page.result.videos) {
      final id = v.id;
      if (id == null || id.isEmpty) continue;
      out.add(YtTrack(
        id: id,
        title: v.name ?? 'Unknown title',
        artist: v.uploaderName ?? 'Unknown Artist',
        thumbnail: v.thumbnails.isNotEmpty ? v.thumbnails.last : null,
        duration: Duration(seconds: v.duration ?? 0),
      ));
    }
    return out;
  }

  Future<List<YtTrack>> getRelated(String videoId) async {
    try {
      final info = await VideoExtractor.getRelatedStreams(
        'https://www.youtube.com/watch?v=$videoId',
      );

      final out = <YtTrack>[];
      for (final v in info.videos) {
        final id = v.id;
        if (id == null || id.isEmpty) continue;

        out.add(YtTrack(
          id: id,
          title: v.name ?? 'Unknown title',
          artist: v.uploaderName ?? 'Unknown Artist',
          thumbnail: v.thumbnails.isNotEmpty ? v.thumbnails.last : null,
          duration: Duration(seconds: v.duration ?? 0),
        ));
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  /// Resolve a playable audio URL based on the preferred quality.
  Future<String> getAudioUrl(String videoId, {int dataUsage = 1}) async {
    await requireOnline();
    final info = await VideoExtractor.getStream(
      'https://www.youtube.com/watch?v=$videoId',
    );

    // The current package version only exposes the highest quality.
    final url = info.audioWithHighestQuality?.url;

    if (url == null || url.isEmpty) {
      throw Exception('No audio stream found for $videoId');
    }
    return url;
  }
}
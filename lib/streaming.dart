import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'models.dart';

/// Where online songs come from, and the login for your own music server.
///
/// Kept apart from `Prefs` on purpose: `Prefs` is written into the backup text, and a server password must never be.
class StreamConfig {
  bool audius = true; // the open Audius catalog
  String audiusKey = ''; // optional free key from api.audius.co/plans (more requests per second)
  String subUrl = '', subUser = '', subPass = ''; // your own Navidrome / Subsonic server

  bool get subOn => subUrl.trim().isNotEmpty && subUser.trim().isNotEmpty && subPass.isNotEmpty;
  bool get any => audius || subOn;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'audius': audius,
        'audiusKey': audiusKey,
        'subUrl': subUrl,
        'subUser': subUser,
        'subPass': subPass,
      };

  void load(Map<String, dynamic> j) {
    audius = j['audius'] is bool ? j['audius'] as bool : true;
    audiusKey = j['audiusKey'] is String ? (j['audiusKey'] as String).trim() : '';
    subUrl = j['subUrl'] is String ? j['subUrl'] as String : '';
    subUser = j['subUser'] is String ? j['subUser'] as String : '';
    subPass = j['subPass'] is String ? j['subPass'] as String : '';
  }

  StreamConfig copy() => StreamConfig()..load(toJson());
}

/// Something went wrong while talking to an online source. [message] is written for the person, not for a programmer.
class StreamException implements Exception {
  final String message;
  StreamException(this.message);
  @override
  String toString() => message;
}

/// Everything that talks to the internet for music. Songs it returns are normal [Track]s whose `uri` is a short
/// address such as `audius:AbC12` or `subsonic:77`. The real https address is made at the moment the song starts
/// ([resolve]), so a changed password or server never leaves broken addresses behind in your playlists.
class Streaming {
  static const String _audiusBase = 'https://api.audius.co/v1';
  static const String _app = 'Athana';

  // ------------------------------------------------------------------------------------------ http
  static Future<dynamic> _getJson(Uri uri, {Map<String, String> headers = const <String, String>{}}) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(uri).timeout(const Duration(seconds: 12));
      req.headers.set('User-Agent', 'Athana');
      req.headers.set('Accept', 'application/json');
      for (final e in headers.entries) {
        req.headers.set(e.key, e.value);
      }
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
      if (res.statusCode == 429) throw StreamException('Too many requests. Wait a moment and try again.');
      if (res.statusCode == 401 || res.statusCode == 403) throw StreamException('The server refused the request (${res.statusCode}). Check the key or login.');
      if (res.statusCode < 200 || res.statusCode >= 300) throw StreamException('The server answered with error ${res.statusCode}.');
      return jsonDecode(body);
    } on StreamException {
      rethrow;
    } on TimeoutException {
      throw StreamException('The server took too long to answer.');
    } on HandshakeException {
      throw StreamException('The secure connection failed (certificate problem).');
    } on SocketException {
      throw StreamException('No connection to the server. Check your internet.');
    } on FormatException {
      throw StreamException('The server sent something Athana does not understand.');
    } on IOException {
      throw StreamException('The connection was interrupted.');
    } finally {
      c.close(force: true);
    }
  }

  // ------------------------------------------------------------------------------------------ Audius
  static Future<List<Track>> audiusSearch(StreamConfig c, String query) =>
      _audiusList(c, '/tracks/search', <String, String>{'query': query, 'limit': '30'});

  static Future<List<Track>> audiusTrending(StreamConfig c) =>
      _audiusList(c, '/tracks/trending', <String, String>{'time': 'week', 'limit': '30'});

  static Future<List<Track>> _audiusList(StreamConfig c, String path, Map<String, String> query) async {
    final uri = Uri.parse('$_audiusBase$path').replace(queryParameters: <String, String>{...query, 'app_name': _app});
    final j = await _getJson(uri, headers: c.audiusKey.isEmpty ? const <String, String>{} : <String, String>{'Authorization': 'Bearer ${c.audiusKey}'});
    final data = j is Map ? j['data'] : null;
    if (data is! List) return <Track>[];
    final out = <Track>[];
    for (final e in data) {
      if (e is! Map) continue;
      final t = _audiusTrack(Map<String, dynamic>.from(e));
      if (t != null) out.add(t);
    }
    return out;
  }

  static String _s(dynamic v) => v == null ? '' : v.toString().trim();

  static Track? _audiusTrack(Map<String, dynamic> m) {
    final id = _s(m['id']);
    if (id.isEmpty) return null;
    // Some tracks are deleted, private or only for paying fans; they cannot be streamed.
    if (m['is_streamable'] == false || m['is_delete'] == true || m['is_stream_gated'] == true) return null;
    final user = m['user'];
    final artist = user is Map ? (_s(user['name']).isNotEmpty ? _s(user['name']) : _s(user['handle'])) : '';
    final art = m['artwork'];
    var artUrl = '';
    if (art is Map) {
      for (final k in <String>['480x480', '1000x1000', '150x150']) {
        if (_s(art[k]).isNotEmpty) {
          artUrl = _s(art[k]);
          break;
        }
      }
    }
    final dur = m['duration'];
    final title = _s(m['title']);
    return Track(
      uri: 'audius:$id',
      name: 'audius_$id.mp3',
      size: -1,
      title: title.isEmpty ? 'Untitled' : title,
      artist: artist,
      genre: _s(m['genre']),
      durationMs: dur is num ? (dur * 1000).round() : 0,
      art: artUrl.isEmpty ? null : artUrl,
      metaDone: true,
    );
  }

  // ------------------------------------------------------------------------------------------ Subsonic / Navidrome
  static String _subBase(StreamConfig c) {
    var u = c.subUrl.trim();
    if (!u.contains('://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static String _salt() {
    final r = Random.secure();
    return List<String>.generate(12, (int _) => r.nextInt(16).toRadixString(16)).join();
  }

  /// A Subsonic address with the login attached the way the protocol wants it (a salted token, never the password itself).
  static Uri _sub(StreamConfig c, String method, Map<String, String> extra) {
    final salt = _salt();
    final token = md5.convert(utf8.encode('${c.subPass}$salt')).toString();
    return Uri.parse('${_subBase(c)}/rest/$method.view').replace(queryParameters: <String, String>{
      'u': c.subUser.trim(),
      't': token,
      's': salt,
      'v': '1.16.1',
      'c': _app,
      'f': 'json',
      ...extra,
    });
  }

  static Future<Map<String, dynamic>> _subCall(StreamConfig c, String method, Map<String, String> extra) async {
    final Uri uri;
    try {
      uri = _sub(c, method, extra);
    } on FormatException {
      throw StreamException('The server address is not valid.');
    }
    final j = await _getJson(uri);
    final r = j is Map ? j['subsonic-response'] : null;
    if (r is! Map) throw StreamException('That address is not a Subsonic or Navidrome server.');
    if (r['status'] != 'ok') {
      final e = r['error'];
      final code = e is Map ? e['code'] : null;
      if (code == 40 || code == 41) throw StreamException('The server refused the user name or password.');
      throw StreamException(e is Map && e['message'] is String ? e['message'] as String : 'The server reported an error.');
    }
    return Map<String, dynamic>.from(r);
  }

  static Future<List<Track>> subSearch(StreamConfig c, String query) async {
    final r = await _subCall(c, 'search3', <String, String>{'query': query, 'songCount': '40', 'albumCount': '0', 'artistCount': '0'});
    final sr = r['searchResult3'];
    return _subSongs(c, sr is Map ? sr['song'] : null);
  }

  static Future<List<Track>> subRandom(StreamConfig c) async {
    final r = await _subCall(c, 'getRandomSongs', <String, String>{'size': '30'});
    final sr = r['randomSongs'];
    return _subSongs(c, sr is Map ? sr['song'] : null);
  }

  /// Returns a short message when the server answers, or throws a [StreamException] that says what is wrong.
  static Future<String> subTest(StreamConfig c) async {
    final r = await _subCall(c, 'ping', <String, String>{});
    final v = _s(r['version']);
    return v.isEmpty ? 'Connected.' : 'Connected (Subsonic API $v).';
  }

  static List<Track> _subSongs(StreamConfig c, dynamic list) {
    if (list is! List) return <Track>[];
    final out = <Track>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      if (m['isDir'] == true) continue;
      final id = _s(m['id']);
      if (id.isEmpty) continue;
      final suffix = _s(m['suffix']).toLowerCase();
      final cover = _s(m['coverArt']);
      final dur = m['duration'];
      final size = m['size'];
      final bits = m['bitDepth'];
      final rate = m['samplingRate'];
      final title = _s(m['title']);
      out.add(Track(
        uri: 'subsonic:$id',
        name: 'sub_$id.${suffix.isEmpty ? 'mp3' : suffix}',
        size: size is num ? size.toInt() : -1,
        title: title.isEmpty ? 'Untitled' : title,
        artist: _s(m['artist']),
        album: _s(m['album']),
        genre: _s(m['genre']),
        year: _s(m['year']),
        durationMs: dur is num ? (dur * 1000).round() : 0,
        bits: bits is num ? bits.toInt() : 0,
        rate: rate is num ? rate.toInt() : 0,
        art: cover.isEmpty ? null : _sub(c, 'getCoverArt', <String, String>{'id': cover, 'size': '500'}).toString(),
        metaDone: true,
      ));
    }
    return out;
  }

  // ------------------------------------------------------------------------------------------ playing
  /// The real https address of an online song, made right now. Throws a [StreamException] when the source is not set up.
  static String resolve(StreamConfig c, Track t) {
    if (t.uri.startsWith('audius:')) {
      final id = t.uri.substring('audius:'.length);
      return Uri.parse('$_audiusBase/tracks/${Uri.encodeComponent(id)}/stream').replace(queryParameters: <String, String>{'app_name': _app}).toString();
    }
    if (t.uri.startsWith('subsonic:')) {
      if (!c.subOn) throw StreamException('Your music server is not set up. Open Search, choose Online, then tap the gear.');
      // format=raw sends the original file untouched, so a FLAC on your server arrives as FLAC.
      try {
        return _sub(c, 'stream', <String, String>{'id': t.uri.substring('subsonic:'.length), 'format': 'raw'}).toString();
      } on FormatException {
        throw StreamException('The server address is not valid.');
      }
    }
    throw StreamException('Athana does not know where this song comes from.');
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

/// Finds a song's cover and tags on MusicBrainz (the data is public domain) and the Cover Art Archive.
/// It only runs when the person taps "Find cover and tags online". MusicBrainz asks apps to send one request per second at most
/// and to say who they are, so both are done here.

const String _ua = 'AthanaMelody/2.1.3 ( https://github.com/Kanatahiroshi25/Athana-Release )';

/// One possible match.
class MbHit {
  final String title, artist, album, year, release, group;
  final int score, lengthMs;
  const MbHit({required this.title, required this.artist, this.album = '', this.year = '', this.release = '', this.group = '', this.score = 0, this.lengthMs = 0});
}

DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

Future<(int, Uint8List)> _fetch(String url, {int maxBytes = 8 * 1024 * 1024}) {
  Future<(int, Uint8List)> run() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', _ua);
      req.headers.set('Accept', 'application/json, image/*');
      final res = await req.close();
      final out = BytesBuilder(copy: false);
      await for (final chunk in res) {
        out.add(chunk);
        if (out.length > maxBytes) break;
      }
      return (res.statusCode, out.takeBytes());
    } finally {
      c.close(force: true);
    }
  }

  return run().timeout(const Duration(seconds: 25));
}

/// Waits so that MusicBrainz gets well under one request per second from this phone (they refuse everything above that).
Future<void> _pace() async {
  final wait = 2200 - DateTime.now().difference(_lastCall).inMilliseconds;
  if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
  _lastCall = DateTime.now();
}

String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// "【LIVE】 Song name (2021 Remaster)" -> "Song name"
String cleanForSearch(String s) {
  var t = s.trim();
  t = t.replaceFirst(RegExp(r'^(?:[\[【(][^\]】)]*[\]】)]\s*)+'), '');
  t = t.replaceAll(RegExp(r'\s*[\[(（【][^\])）】]*(?:remaster|remix|live|ver\.?|version|edit|mono|stereo)[^\])）】]*[\])）】]', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? s.trim() : t;
}

String _credit(dynamic ac) {
  if (ac is! List) return '';
  final b = StringBuffer();
  for (final e in ac) {
    if (e is Map) {
      b.write((e['name'] ?? (e['artist'] is Map ? (e['artist'] as Map)['name'] : '') ?? '').toString());
      b.write((e['joinphrase'] ?? '').toString());
    }
  }
  return b.toString().trim();
}

List<MbHit> _parse(dynamic json) {
  final out = <MbHit>[];
  final seen = <String>{};
  if (json is! Map) return out;
  final recs = json['recordings'];
  if (recs is! List) return out;
  for (final r in recs) {
    if (r is! Map) continue;
    final title = (r['title'] ?? '').toString();
    if (title.isEmpty) continue;
    final artist = _credit(r['artist-credit']);
    final score = r['score'] is num ? (r['score'] as num).toInt() : 0;
    final len = r['length'] is num ? (r['length'] as num).toInt() : 0;
    final rels = r['releases'] is List ? (r['releases'] as List).whereType<Map>().toList() : <Map>[];
    // Dated releases first, so the year is known.
    rels.sort((Map a, Map b) => ((a['date'] ?? '').toString().isEmpty ? 1 : 0).compareTo((b['date'] ?? '').toString().isEmpty ? 1 : 0));
    if (rels.isEmpty) {
      if (seen.add('$title|$artist|')) out.add(MbHit(title: title, artist: artist, score: score, lengthMs: len));
    }
    for (final rel in rels.take(2)) {
      final album = (rel['title'] ?? '').toString();
      if (!seen.add('$title|$artist|$album')) continue;
      final date = (rel['date'] ?? '').toString();
      final year = RegExp(r'^\d{4}').firstMatch(date)?.group(0) ?? '';
      final group = rel['release-group'] is Map ? ((rel['release-group'] as Map)['id'] ?? '').toString() : '';
      out.add(MbHit(title: title, artist: artist, album: album, year: year, release: (rel['id'] ?? '').toString(), group: group, score: score, lengthMs: len));
    }
    if (out.length >= 12) break;
  }
  return out;
}

/// Searches already done in this session, so asking again for the same song sends nothing.
final Map<String, List<MbHit>> _cache = <String, List<MbHit>>{};

/// One request. When MusicBrainz says it is busy (503 or 429) it waits a few seconds and tries once more.
Future<(int, Uint8List)> _search(String q, {String what = 'recording'}) async {
  final url = 'https://musicbrainz.org/ws/2/$what/?query=${Uri.encodeQueryComponent(q)}&fmt=json&limit=${what == 'recording' ? 10 : 3}';
  await _pace();
  var r = await _fetch(url);
  if (r.$1 == 503 || r.$1 == 429) {
    await Future<void>.delayed(const Duration(seconds: 4));
    _lastCall = DateTime.now();
    r = await _fetch(url);
  }
  return r;
}

/// The MusicBrainz id of an artist, found by name. The English spelling of a Japanese band is usually an alias, so aliases and the
/// sort name count too. Empty when no artist is a clear match.
Future<String> _artistId(String name) async {
  final n = _esc(name);
  final (code, body) = await _search('artist:"$n" OR alias:"$n" OR sortname:"$n"', what: 'artist');
  if (code != 200) {
    debugPrint('[musicbrainz] artist search answered $code');
    return '';
  }
  final j = jsonDecode(utf8.decode(body, allowMalformed: true));
  if (j is! Map || j['artists'] is! List) return '';
  final list = (j['artists'] as List).whereType<Map>().toList();
  for (final a in list) {
    debugPrint('[musicbrainz] artist candidate: ${a['name']} (score ${a['score']})');
  }
  for (final a in list) {
    final score = a['score'] is num ? (a['score'] as num).toInt() : 0;
    if (score >= 75) return (a['id'] ?? '').toString();
    break;
  }
  return '';
}

/// Names worth trying for an artist: as written, without a trailing bracket, and the voice actor of a "(CV. name)" credit.
List<String> _artistNames(String a) {
  final out = <String>[a];
  final base = a.replaceFirst(RegExp(r'\s*[(（\[【][^)）\]】]*[)）\]】]\s*$'), '').trim();
  if (base.isNotEmpty && !out.contains(base)) out.add(base);
  final cv = RegExp(r'[(（]\s*(?:CV|cv|C\.V)[.:：\s]*([^)）]+)[)）]').firstMatch(a);
  final who = cv?.group(1)?.trim() ?? '';
  if (who.isNotEmpty && !out.contains(who)) out.add(who);
  // Several artists written as one text ("A, B & C", "A feat. B", "A x B"): each one on its own.
  final parts = a.split(RegExp(r'\s*(?:,|、|;|&|/|×|\+|\bfeat\.?|\bft\.?|\bfeaturing\b|\bwith\b|\sx\s)\s*', caseSensitive: false));
  for (final raw in parts) {
    final part = raw.trim();
    if (part.isNotEmpty && part != a && !out.contains(part)) out.add(part);
  }
  return out.length > 6 ? out.sublist(0, 6) : out;
}

/// The title as plain words ("WHY?MYSTERY?!ANSWER" -> "WHY MYSTERY ANSWER"), for a looser search.
String _words(String t) => t.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

/// Searches recordings by title and artist. MusicBrainz keeps titles in the song's own language (a Japanese song is listed in
/// Japanese), so when the typed title finds nothing it also looks for the artist's recording with the same length.
/// Throws a short message (String) when the service cannot be reached.
Future<List<MbHit>> mbSearch(String title, String artist, {int durMs = 0}) async {
  final t = cleanForSearch(title);
  final a = cleanForSearch(artist);
  if (t.isEmpty) return const <MbHit>[];
  final key = '${t.toLowerCase()}|${a.toLowerCase()}|${durMs ~/ 1000}';
  final known = _cache[key];
  if (known != null) return known;
  final w = _words(t);
  final names = a.isEmpty ? const <String>[] : _artistNames(a);
  final first = names.isEmpty ? '' : (names.length > 1 ? names[1] : names[0]);
  final queries = <String>[
    if (a.isNotEmpty) 'recording:"${_esc(t)}" AND artist:"${_esc(a)}"',
    'recording:"${_esc(t)}"',
    // The same words without the punctuation, which MusicBrainz often spells differently.
    if (w.isNotEmpty && w != t && first.isNotEmpty) 'recording:"${_esc(w)}" AND artist:"${_esc(first)}"',
    if (w.isNotEmpty && w != t) 'recording:"${_esc(w)}"',
  ];
  List<MbHit> run((int, Uint8List) r) {
    if (r.$1 == 503 || r.$1 == 429) throw 'MusicBrainz is busy right now (it allows about one request a second per internet connection). Wait a minute, then search again.';
    if (r.$1 != 200) throw 'MusicBrainz answered with an error (${r.$1}).';
    return _parse(jsonDecode(utf8.decode(r.$2, allowMalformed: true)));
  }

  for (final q in queries) {
    final hits = run(await _search(q));
    if (hits.isNotEmpty) {
      _cache[key] = hits;
      return hits;
    }
  }
  // Nothing under that title (it may be written in Japanese there): the same artist with about the same length.
  if (a.isNotEmpty && durMs > 0) {
    var id = '';
    for (final n in _artistNames(a)) {
      id = await _artistId(n);
      debugPrint('[musicbrainz] artist "$n" -> ${id.isEmpty ? 'not found' : id}');
      if (id.isNotEmpty) break;
    }
    if (id.isNotEmpty) {
      final lo = durMs - 8000, hi = durMs + 8000;
      final hits = run(await _search('arid:$id AND dur:[$lo TO $hi]'));
      debugPrint('[musicbrainz] same artist, length $lo-$hi ms -> ${hits.length} found');
      if (hits.isNotEmpty) {
        // The closest length first, so the right song is on top.
        hits.sort((MbHit x, MbHit y) => (x.lengthMs - durMs).abs().compareTo((y.lengthMs - durMs).abs()));
        _cache[key] = hits;
        return hits;
      }
    }
  } else {
    debugPrint('[musicbrainz] no length search: artist "${a.isEmpty ? '' : a}", length $durMs ms');
  }
  _cache[key] = const <MbHit>[];
  return const <MbHit>[];
}

bool _isImage(Uint8List b) =>
    b.length > 2000 && ((b[0] == 0xFF && b[1] == 0xD8) || (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47));

/// The front cover of the release, or else of its release group. Null when there is none.
Future<Uint8List?> mbCover(MbHit h) async {
  final urls = <String>[
    if (h.release.isNotEmpty) 'https://coverartarchive.org/release/${h.release}/front-500',
    if (h.group.isNotEmpty) 'https://coverartarchive.org/release-group/${h.group}/front-500',
  ];
  for (final u in urls) {
    try {
      final (code, body) = await _fetch(u);
      if (code == 200 && _isImage(body)) return body;
    } catch (_) {}
  }
  return null;
}

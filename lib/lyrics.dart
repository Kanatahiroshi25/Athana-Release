import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'models.dart';
import 'native.dart';
import 'romanize.dart';

/// Languages the lyrics can be translated into (the same list as the web version).
const Map<String, String> kTrLangs = {
  'id': 'Indonesian', 'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German', 'pt': 'Portuguese', 'it': 'Italian',
  'ru': 'Russian', 'ja': 'Japanese', 'ko': 'Korean', 'zh-CN': 'Chinese', 'ar': 'Arabic', 'hi': 'Hindi', 'tr': 'Turkish',
  'th': 'Thai', 'vi': 'Vietnamese', 'ms': 'Malay', 'tl': 'Filipino',
};

/// One word with its own timing: it fills in while it is being sung.
class LyricWord {
  final String text;
  int ms; // when the word starts
  int dur; // how long the fill takes
  LyricWord(this.text, this.ms, this.dur);

  /// 0 before the word, 1 after it has been sung.
  double progress(int now) => dur <= 0 ? (now >= ms ? 1 : 0) : ((now - ms) / dur).clamp(0.0, 1.0);
}

class LyricLine {
  final int? ms; // null for lyrics without time stamps
  final String text;
  String? tr; // translation
  String? ro; // romaji
  List<LyricWord>? words; // word-by-word timing, when there is some
  LyricLine(this.ms, this.text);
}

class LyricsData {
  final List<LyricLine> lines;
  final bool synced;
  final bool jp;
  String source = '';
  LyricsData(this.lines, this.synced, this.jp);
}

final RegExp _stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
final RegExp _wordStamp = RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>');
/// Enhanced LRC word timing: <mm:ss.xx> followed by the word itself.
final RegExp _wordFull = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>([^<]*)');
final RegExp _metaTag = RegExp(r'^\s*\[(ar|ti|al|by|au|length|re|ve|id):', caseSensitive: false);
final RegExp _offsetTag = RegExp(r'^\s*\[offset:\s*([+-]?\d+)\]', caseSensitive: false);
final RegExp _kana = RegExp('[぀-ヿ]');
final RegExp _jpChar = RegExp('[぀-ヿ一-鿿]');

bool hasJp(String s) => _jpChar.hasMatch(s);
/// The line that is being sung at a position, or -1 when none is.
int activeLine(LyricsData d, int pos) {
  if (!d.synced) return -1;
  var lo = 0, hi = d.lines.length - 1, r = -1;
  while (lo <= hi) {
    final m = (lo + hi) ~/ 2;
    final ms = d.lines[m].ms;
    if (ms == null || d.lines[m].text.isEmpty) {
      hi = m - 1;
      continue;
    }
    if (ms <= pos) {
      r = m;
      lo = m + 1;
    } else {
      hi = m - 1;
    }
  }
  return r;
}

/// Turns plain or LRC text into lyrics. Returns null when there is nothing in it.
LyricsData? buildLyrics(String text) {
  var offset = 0;
  final rows = <LyricLine>[];
  int ts(RegExpMatch m) {
    final frac = m.group(3);
    final f = frac == null ? 0 : (double.parse('0.$frac') * 1000).round();
    return (int.parse(m.group(1)!) * 60000 + int.parse(m.group(2)!) * 1000 + f - offset).clamp(0, 1 << 40).toInt();
  }
  for (final row in text.replaceAll('\r', '').split('\n')) {
    final om = _offsetTag.firstMatch(row);
    if (om != null) {
      offset = int.tryParse(om.group(1)!) ?? 0;
      continue;
    }
    if (_metaTag.hasMatch(row)) continue;
    final stamps = _stamp.allMatches(row).toList();
    final body = row.replaceAll(_stamp, '').replaceAll(_wordStamp, '').trim();
    if (stamps.isEmpty) {
      rows.add(LyricLine(null, body));
    } else {
      List<LyricWord>? words;
      if (stamps.length == 1) {
        final ws = <LyricWord>[];
        for (final m in _wordFull.allMatches(row)) {
          ws.add(LyricWord(m.group(4)!.trim(), ts(m), 0));
        }
        while (ws.isNotEmpty && ws.last.text.isEmpty) {
          ws.removeLast();
        }
        if (ws.length >= 2) words = ws;
      }
      for (final m in stamps) {
        final l = LyricLine(ts(m), body);
        l.words = words;
        rows.add(l);
      }
    }
  }
  final timed = rows.where((l) => l.ms != null && l.text.isNotEmpty).toList();
  List<LyricLine> lines;
  var synced = false;
  if (timed.length >= 2) {
    timed.sort((a, b) => a.ms!.compareTo(b.ms!));
    lines = timed;
    synced = true;
    _fillWordTimes(lines);
  } else {
    lines = [for (final l in rows) LyricLine(null, l.text)];
    while (lines.isNotEmpty && lines.first.text.isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.text.isEmpty) {
      lines.removeLast();
    }
    final kept = <LyricLine>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].text.isNotEmpty || (i > 0 && lines[i - 1].text.isNotEmpty)) kept.add(lines[i]);
    }
    lines = kept;
  }
  if (lines.isEmpty) return null;
  final filled = lines.where((l) => l.text.isNotEmpty).toList();
  final kana = filled.where((l) => _kana.hasMatch(l.text) || hasHangul(l.text)).length;
  return LyricsData(lines, synced, kana >= (filled.length * 0.2).clamp(1, 1 << 30));
}

int _clampi(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

int _guessLineDur(String text) => _clampi(450 * text.split(RegExp(r'\s+')).length, 1800, 7000);

void _fillWordTimes(List<LyricLine> lines) {
  const reveal = 240;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final start = l.ms;
    if (start == null || l.text.isEmpty) continue;
    final nextMs = i + 1 < lines.length ? lines[i + 1].ms : null;
    var span = (nextMs ?? start + _guessLineDur(l.text)) - start;
    if (span <= 0) span = 800;
    if (l.words != null) {
      final ws = l.words!;
      for (final w in ws) {
        if (w.ms < start) w.ms = start;
      }
      for (var k = 0; k < ws.length; k++) {
        final end = k + 1 < ws.length ? ws[k + 1].ms : start + span;
        ws[k].dur = _clampi(end - ws[k].ms - 40, reveal, 2000);
      }
      continue;
    }
    final parts = l.text.split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
    if (parts.isEmpty) continue;
    var total = 0;
    final weights = <int>[];
    for (final w in parts) {
      weights.add(w.length + 2);
      total += w.length + 2;
    }
    final usable = span > 200 ? span - 120 : span;
    final ws = <LyricWord>[];
    var t = start;
    for (var k = 0; k < parts.length; k++) {
      ws.add(LyricWord(parts[k], t, 0));
      t += (weights[k] * usable / total).round();
    }
    for (var k = 0; k < ws.length; k++) {
      final end = k + 1 < ws.length ? ws[k + 1].ms : start + span;
      ws[k].dur = _clampi(end - ws[k].ms - 40, reveal, 700);
    }
    l.words = ws;
  }
}

// ------------------------------------------------------------------------- small web helpers
class _Resp {
  final int status;
  final String body;
  _Resp(this.status, this.body);
}

Future<_Resp?> _get(String url) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 12));
    req.headers.set('User-Agent', 'Athana/2.0 (+https://github.com/Kanatahiroshi25/Athana-Release)');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    return _Resp(res.statusCode, body);
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}

String _q(Map<String, String> p) => p.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

String _norm(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    b.writeCharCode((r >= 0xFF01 && r <= 0xFF5E) ? r - 0xFEE0 : r);
  }
  return b.toString().toLowerCase().replaceAll(RegExp('[\\s\\-_.,\'\"!?:;~・〜()\\[\\]【】「」『』]+'), '');
}

String _clean(String s) => s
    .replaceAll(RegExp(r'\s*[(\[][^)\]]*[)\]]\s*'), ' ')
    .replaceAll(RegExp(r'\s+-\s+.*$'), '')
    .replaceAll(RegExp(r'\s+(feat|ft)\.?\s.*$', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _badArtist(String a) => a.trim().isEmpty || RegExp(r'^(various artists?|various|unknown artist|va)$', caseSensitive: false).hasMatch(a.trim());

String _hash(String s) {
  var h = 5381;
  for (final c in s.codeUnits) {
    h = ((h << 5) + h + c) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

String _trNorm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

bool hasJpLine(String s) => hasJp(s);

// ------------------------------------------------------------------------- search results
class LyricHit {
  final String title;
  final String sub;
  final String kind; // 'word' = word by word, 'line' = synced, 'plain'
  final String source;
  final String lrc;
  final int score;
  LyricHit(this.title, this.sub, this.kind, this.source, this.lrc, this.score);
}

// ------------------------------------------------------------------------ Lyrica API
Future<List<LyricHit>> _lyrica(String title, String artist, {int durSec = 0}) async {
  final out = <LyricHit>[];
  try {
    final cleanT = _clean(title);
    final cleanA = artist.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();

    final url = Uri.parse('https://wilooper-lyrica.hf.space/lyrics/').replace(
      queryParameters: {
        'artist': cleanA,
        'song': cleanT,
        'timestamps': 'true',
        'fast': 'true',
      },
    ).toString();

    final r = await _get(url);
    if (r != null && r.status == 200) {
      final j = jsonDecode(r.body);
      if (j is Map && j['status'] == 'success' && j['data'] != null) {
        final data = j['data'];
        final lrc = (data['lrc'] ?? data['lyrics'] ?? '').toString();
        if (lrc.trim().isNotEmpty) {
          final wordy = RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>').allMatches(lrc).length >= 6;
          final kind = wordy ? 'word' : 'line';
          final source = data['source']?.toString() ?? 'Lyrica';

          // Give Lyrica a high base score so its results float to the top
          var sc = 100 + (wordy ? 200 : 0) + (durSec > 0 ? 10 : 0);
          out.add(LyricHit(cleanT, cleanA, kind, source, lrc, sc));
        }
      }
    }
  } catch (e) {
    debugPrint('Lyrica API error: $e');
  }
  return out;
}

// ------------------------------------------------------------------------ NetEase (word by word)
String _klyricToLrc(Map k) {
  String ms2(int ms) {
    final m = ms ~/ 60000, s = (ms ~/ 1000) % 60, c = (ms ~/ 10) % 100;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${c.toString().padLeft(2, '0')}';
  }

  final sb = StringBuffer();
  final lines = k['lyric'] is Map ? (k['lyric'] as Map)['data'] as List? : null;
  if (lines == null) return '';
  for (final line in lines) {
    if (line is! Map) continue;
    final start = ((line['startTime'] ?? 0) as num).toInt();
    final words = line['words'];
    if (words is! List) {
      final t = (line['content'] ?? '').toString();
      if (t.isNotEmpty) sb.writeln('[$ms2(start)]$t');
      continue;
    }
    final sbw = StringBuffer();
    for (final w in words) {
      if (w is! Map) continue;
      final ws = ((w['startTime'] ?? 0) as num).toInt();
      final wt = (w['rawData'] ?? w['content'] ?? '').toString();
      if (wt.isEmpty) continue;
      sbw.write('<$ms2(ws)>$wt ');
    }
    final row = sbw.toString().trim();
    if (row.isNotEmpty) sb.writeln('[$ms2(start)]$row');
  }
  return sb.toString();
}

String _ms2(int ms) {
  final m = ms ~/ 60000, s = (ms ~/ 1000) % 60, c = (ms ~/ 10) % 100;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${c.toString().padLeft(2, '0')}';
}

final RegExp _yrcLine = RegExp(r'^\[(\d+),(\d+)\](.*)$');
final RegExp _yrcWord = RegExp(r'\((\d+),(\d+),-?\d+\)');

String _yrcToLrc(String y) {
  final sb = StringBuffer();
  for (final raw in y.replaceAll('\r', '').split('\n')) {
    final lm = _yrcLine.firstMatch(raw.trim());
    if (lm == null) continue;
    final start = int.parse(lm.group(1)!);
    final body = lm.group(3)!;
    final ms = _yrcWord.allMatches(body).toList();
    if (ms.isEmpty) continue;
    final row = StringBuffer();
    for (var k = 0; k < ms.length; k++) {
      final end = k + 1 < ms.length ? ms[k + 1].start : body.length;
      final text = body.substring(ms[k].end, end);
      if (text.trim().isEmpty) {
        row.write(text.isEmpty ? '' : ' ');
        continue;
      }
      row.write('<${_ms2(int.parse(ms[k].group(1)!))}>$text');
    }
    final line = row.toString().trim();
    if (line.isNotEmpty) sb.writeln('[${_ms2(start)}]$line');
  }
  return sb.toString();
}

Future<List<LyricHit>> _netease(String title, String artist, {int durSec = 0}) async {
  final out = <LyricHit>[];
  final q = Uri.encodeComponent('${artist.isNotEmpty ? '$artist ' : ''}$title');
  final r = await _get('https://music.163.com/api/search/get/web?s=$q&type=1&offset=0&limit=8');
  if (r == null || r.status != 200) return out;
  try {
    final j = jsonDecode(r.body);
    final songs = (j is Map && j['result'] is Map) ? (j['result'] as Map)['songs'] as List? : null;
    if (songs == null) return out;
    for (final s in songs.take(6)) {
      fetchNext:
      {
        if (s is! Map) break fetchNext;
        final id = s['id'];
        if (id == null) break fetchNext;
        final name = (s['name'] ?? '').toString();
        final ar = s['artists'] is List && (s['artists'] as List).isNotEmpty && (s['artists'] as List)[0] is Map ? ((s['artists'] as List)[0] as Map)['name'].toString() : '';
        final dur = ((s['duration'] ?? 0) as num).toInt() ~/ 1000;
        if (durSec > 0 && dur > 0 && (dur - durSec).abs() > 10) break fetchNext;

        var lr = await _get('https://music.163.com/api/song/lyric/v1?id=$id&lv=-1&kv=-1&tv=-1&rv=-1&yv=-1&ytv=-1&yrv=-1');
        Object? j2;
        try {
          j2 = (lr != null && lr.status == 200) ? jsonDecode(lr.body) : null;
        } catch (_) {
          j2 = null;
        }
        if (j2 is! Map || (j2['lrc'] == null && j2['yrc'] == null)) {
          lr = await _get('https://music.163.com/api/song/lyric?id=$id&lv=1&kv=1&tv=-1');
          if (lr == null || lr.status != 200) break fetchNext;
          j2 = jsonDecode(lr.body);
        }
        if (j2 is! Map) break fetchNext;
        String lrc = '';
        String kind = 'plain';
        var bonus = 0;
        final yr = j2['yrc'];
        if (yr is Map && yr['lyric'] is String) {
          lrc = _yrcToLrc(yr['lyric'] as String);
          if (lrc.isNotEmpty) {
            kind = 'word';
            bonus = 260;
          }
        }
        final k = j2['klyric'];
        if (lrc.isEmpty && k is Map && k['lyric'] is Map) {
          lrc = _klyricToLrc(k);
          if (lrc.isNotEmpty) {
            kind = 'word';
            bonus = 200;
          }
        }
        if (lrc.isEmpty && j2['lrc'] is Map && (j2['lrc'] as Map)['lyric'] is String) {
          lrc = (j2['lrc'] as Map)['lyric'] as String;
          kind = 'line';
        }
        if (lrc.trim().isEmpty) break fetchNext;
        final album = s['album'] is Map ? ((s['album'] as Map)['name'] ?? '').toString() : '';
        var sc = bonus + (durSec > 0 && dur > 0 && (dur - durSec).abs() <= 2 ? 30 : 0) + (_norm(name) == _norm(title) ? 20 : 0);
        out.add(LyricHit(name, [ar, album].where((x) => x.toString().isNotEmpty).join(' · '), kind, 'NetEase', lrc, sc));
      }
    }
  } catch (_) {}
  return out;
}

// ------------------------------------------------------------------------ search everywhere
const List<String> _kinds = ['word', 'line', 'plain'];
int _kindRank(String k) => _kinds.indexOf(k);

Future<List<LyricHit>> searchAll(Track t, String? custom) async {
  final dur = (t.durationMs / 1000).round();
  final artists = <String>[t.artist, t.albumArtist].where((a) => !_badArtist(a)).toSet().toList();
  final titles = <String>[t.title, _clean(t.title)].where((x) => x.isNotEmpty).toSet().toList();
  final q = custom ?? (titles.isNotEmpty ? titles.first : '');
  if (q.isEmpty) return const [];
  final out = <LyricHit>[];

  final qa = artists.isNotEmpty ? artists.first : '';

  // 1. LRCLIB Search
  final lrclib = () async {
    try {
      final urls = <String>['https://lrclib.net/api/search?${_q({'q': q})}'];
      if (custom == null && artists.isNotEmpty) {
        urls.add('https://lrclib.net/api/search?${_q({'track_name': _clean(q), 'artist_name': artists.first})}');
      }
      final got = await Future.wait(urls.map(_get));
      final j = <dynamic>[];
      final ids = <Object?>{};
      for (final r in got) {
        if (r == null || r.status != 200) continue;
        try {
          final one = jsonDecode(r.body);
          if (one is List) {
            for (final x in one) {
              if (x is Map && !ids.add(x['id'] ?? x.hashCode)) continue;
              j.add(x);
            }
          }
        } catch (_) {}
      }
      for (final x in j.take(12)) {
        if (x is! Map) continue;
        final syncedL = (x['syncedLyrics'] ?? '').toString();
        final plainL = (x['plainLyrics'] ?? '').toString();
        if (syncedL.isEmpty && plainL.isEmpty) continue;
        final rt = (x['trackName'] ?? x['name'] ?? '').toString();
        final ra = (x['artistName'] ?? '').toString();
        final album = (x['albumName'] ?? '').toString();
        final rd = ((x['duration'] ?? 0) as num).toInt();
        var sc = 0;
        if (syncedL.isNotEmpty) sc += 60;
        if (dur > 0 && rd > 0) {
          final d = (rd - dur).abs();
          sc += d <= 2 ? 30 : (d <= 5 ? 20 : (d <= 10 ? 5 : -200));
        }
        if (_norm(rt) == _norm(q)) sc += 20;
        final wordy = RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>').allMatches(syncedL).length >= 6;
        if (wordy) sc += 200;
        out.add(LyricHit(rt, [ra, album].where((x2) => x2.isNotEmpty).join(' · '), wordy ? 'word' : (syncedL.isNotEmpty ? 'line' : 'plain'), 'lrclib.net', syncedL.isNotEmpty ? syncedL : plainL, sc));
      }
    } catch (_) {}
  }();

  // 2. NetEase Search
  final variants = <List<String>>[
    [q, qa],
    if (_clean(q) != q) [_clean(q), qa],
    if (qa.isNotEmpty) [_clean(q), ''],
  ];
  final seenKey = <String>{};
  final netease = Future.wait(variants.map((v) => _netease(v[0], v[1], durSec: dur).catchError((Object _) => <LyricHit>[]))).then((lists) {
    for (final list in lists) {
      for (final h in list) {
        if (seenKey.add('${h.kind}:${h.lrc.hashCode}')) out.add(h);
      }
    }
  }).catchError((Object _) {});

  // 3. Lyrica Search (Aggregates Musixmatch, Genius, etc.)
  final lyrica = _lyrica(q, qa, durSec: dur).then((hits) {
    for (final h in hits) {
      if (seenKey.add('${h.kind}:${h.lrc.hashCode}')) out.add(h);
    }
  }).catchError((Object _) {});

  // Wait for all 3 to finish in parallel
  await Future.wait([lrclib, netease, lyrica]);

  // the old extras, only when nothing good was found
  try {
    if (custom == null && out.isEmpty) {
      final uma = RegExp('ウマ娘|umamusume|WINNING LIVE|STARTING GATE|\\bCV[.．:：]', caseSensitive: false).hasMatch([t.album, t.artist, t.albumArtist, t.title].join(' '));
      if (uma) {
        final x = await _wikiLyrics(t.title);
        if (x != null) out.add(LyricHit(t.title, 'Umamusume Wiki', 'plain', 'Umamusume Wiki', x, 5));
      } else if (artists.isNotEmpty && !hasJp(t.title)) {
        final r = await _get('https://api.lyrics.ovh/v1/${Uri.encodeComponent(artists.first)}/${Uri.encodeComponent(_clean(t.title))}');
        if (r != null && r.status == 200) {
          final j = jsonDecode(r.body);
          final l = (j is Map ? (j['lyrics'] ?? '') : '').toString();
          if (l.trim().length > 40) {
            out.add(LyricHit(t.title, artists.first, 'plain', 'lyrics.ovh', l.replaceFirst(RegExp(r'^Paroles de la chanson[^\n]*\n', caseSensitive: false), '').trim(), 5));
          }
        }
      }
    }
  } catch (_) {}

  out.sort((a, b) {
    final k = _kindRank(a.kind) - _kindRank(b.kind);
    if (k != 0) return k;
    return b.score - a.score;
  });
  final seen = <String>{};
  return [for (final h in out) if (seen.add('${h.source}:${h.lrc.hashCode}')) h];
}

// ------------------------------------------------------------------------- the wiki and translate helpers (unchanged)
String _htmlText(String x) {
  return x
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|dd|dt)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'&nbsp;|&#160;'), ' ')
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-f]+);', caseSensitive: false), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'&#0?39;|&apos;'), "'")
      .replaceAll('&amp;', '&');
}

String? _wikiTable(String html) {
  for (final tb in RegExp(r'<table[\s\S]*?</table>', caseSensitive: false).allMatches(html)) {
    final rows = RegExp(r'<tr[\s\S]*?</tr>', caseSensitive: false).allMatches(tb.group(0)!).map((m) => m.group(0)!).toList();
    if (rows.length < 2) continue;
    final cell = RegExp(r'<t[hd][\s\S]*?</t[hd]>', caseSensitive: false);
    final heads = cell.allMatches(rows[0]).map((m) => _htmlText(m.group(0)!).trim().toLowerCase()).toList();
    final ki = heads.indexWhere((c) => c.contains('kanji'));
    if (ki < 0 || !heads.any((c) => c.contains('romaji'))) continue;
    final out = <String>[];
    for (final r in rows.skip(1)) {
      final cells = cell.allMatches(r).map((m) => m.group(0)!).toList();
      if (ki >= cells.length) continue;
      final t = _htmlText(cells[ki]).split('\n').map((l) => l.trim()).join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
      if (t.isNotEmpty) out.add(t);
    }
    if (out.isNotEmpty) return out.join('\n\n');
  }
  return null;
}

Future<String?> _wikiLyrics(String q) async {
  const api = 'https://umamusu.wiki/api.php';
  final key = _norm(q);
  final seen = <String>{};
  Future<dynamic> get(Map<String, String> p) async {
    final r = await _get('$api?${_q({'format': 'json', 'origin': '*', ...p})}');
    if (r == null || r.status != 200) return null;
    try {
      return jsonDecode(r.body);
    } catch (_) {
      return null;
    }
  }

  for (final sr in ['"$q"', q]) {
    final j = await get({'action': 'query', 'list': 'search', 'srsearch': sr, 'srlimit': '4', 'srnamespace': '0'});
    final hits = (j is Map && j['query'] is Map && (j['query'] as Map)['search'] is List) ? (j['query'] as Map)['search'] as List : const [];
    for (final hit in hits) {
      final title = hit is Map ? hit['title'] : null;
      if (title is! String || !seen.add(title)) continue;
      final p = await get({'action': 'parse', 'page': title, 'prop': 'text', 'redirects': '1'});
      final html = (p is Map && p['parse'] is Map && (p['parse'] as Map)['text'] is Map) ? ((p['parse'] as Map)['text'] as Map)['*'] : null;
      if (html is String && _norm(_htmlText(html)).contains('japanese$key')) {
        final x = _wikiTable(html);
        if (x != null) return x;
      }
    }
  }
  return null;
}

// ------------------------------------------------------------------------- translation
const List<List<String>> _casLite = [['saya', 'aku'], ['anda', 'kamu'], ['engkau', 'kamu'], ['dikau', 'kamu']];
const List<List<String>> _casMore = [
  ['tidak', 'nggak'], ['sudah', 'udah'], ['telah', 'udah'], ['hanya', 'cuma'], ['bagaimana', 'gimana'], ['mengapa', 'kenapa'],
  ['seperti', 'kayak'], ['tetapi', 'tapi'], ['namun', 'tapi'], ['agar', 'biar'], ['supaya', 'biar'], ['ingin', 'pengen'],
  ['dapat', 'bisa'], ['apakah', 'apa'], ['kami', 'kita'], ['sedang', 'lagi'], ['benar-benar', 'bener-bener'], ['hendak', 'mau'],
];

String _keepCase(String m, String to) => m.isNotEmpty && m[0] != m[0].toLowerCase() ? to[0].toUpperCase() + to.substring(1) : to;

String casualId(String t) {
  for (final p in [..._casLite, ..._casMore]) {
    t = t.replaceAllMapped(RegExp('\\b${p[0]}\\b', caseSensitive: false), (m) => _keepCase(m.group(0)!, p[1]));
  }
  return t.replaceAllMapped(RegExp(r'\b(sangat)\s+([a-z]+)', caseSensitive: false), (m) => _keepCase(m.group(0)!, '${m.group(2)} banget'));
}

class _Gt {
  final String text;
  final String src;
  final String translit;
  _Gt(this.text, this.src, this.translit);
}

Future<_Gt?> _gtx(String q, String tl, {String sl = 'auto', bool rm = false}) async {
  final r = await _get('https://translate.googleapis.com/translate_a/single?client=gtx&sl=$sl&tl=$tl&dt=t${rm ? '&dt=rm' : ''}&q=${Uri.encodeComponent(q)}');
  if (r == null || r.status != 200) return null;
  try {
    final j = jsonDecode(r.body);
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
  }
}

// ------------------------------------------------------------------------- the controller
class LyricsController extends ChangeNotifier {
  final AppState app;
  LyricsController(this.app);

  LyricsData? data;
  String state = 'none';
  String note = '';
  bool busy = false;
  String _key = '';
  int _gen = 0;
  List<LyricHit> hits = const <LyricHit>[];

  bool get onlineOk => !app.prefs.offline;
  bool get lyricsNetOk => onlineOk && app.prefs.netLyrics;
  bool get transNetOk => onlineOk && app.prefs.netTranslate;
  String get trName => kTrLangs[app.prefs.trLang] ?? app.prefs.trLang;

  String _savedKey(Track t) => 'athana_lyr:${t.key}';

  void ensure(Track? t) {
    if ((t?.key ?? '') != _key) unawaited(load(t));
  }

  Future<void> load(Track? t) async {
    final gen = ++_gen;
    _key = t?.key ?? '';
    data = null;
    note = '';
    busy = false;
    if (t == null) {
      state = 'none';
      notifyListeners();
      return;
    }
    state = 'loading';
    notifyListeners();
    LyricsData? d;
    final saved = app.sp?.getString(_savedKey(t));
    if (saved != null) {
      d = buildLyrics(saved);
      d?.source = 'Saved on this phone';
    }
    if (d == null) {
      try {
        final raw = await Native.lyrics(t.uri);
        if (raw != null) d = buildLyrics(raw);
        d?.source = 'From the song file';
      } catch (_) {}
    }
    if (gen != _gen) return;
    data = d;
    state = d == null ? 'none' : 'ready';
    notifyListeners();
    if (d == null) {
      if (app.prefs.lrcAuto && lyricsNetOk) unawaited(findOnline(quiet: true));
    } else {
      _restoreExtras(t, d);
      if (app.prefs.lyrTr) unawaited(translate());
      if (app.prefs.lyrRo) unawaited(romanize());
    }
  }

  String? saveText(String text) {
    final t = app.current;
    if (t == null) return null;
    final d = buildLyrics(text.trim());
    if (d == null) return 'That text has no lyric lines.';
    d.source = 'Saved on this phone';
    app.sp?.setString(_savedKey(t), text.trim());
    _gen++;
    data = d;
    state = 'ready';
    note = '';
    notifyListeners();
    if (app.prefs.lyrTr) unawaited(translate());
    if (app.prefs.lyrRo) unawaited(romanize());
    return null;
  }

  Future<void> deleteSaved() async {
    final t = app.current;
    if (t == null) return;
    app.sp?.remove(_savedKey(t));
    await load(t);
  }

  bool get hasSaved {
    final t = app.current;
    return t != null && (app.sp?.containsKey(_savedKey(t)) ?? false);
  }

  String get plainText {
    final d = data;
    if (d == null) return '';
    final t = app.current;
    final saved = t == null ? null : app.sp?.getString(_savedKey(t));
    if (saved != null) return saved;
    String stamp(int ms) {
      final m = ms ~/ 60000, s = (ms ~/ 1000) % 60, c = (ms ~/ 10) % 100;
      return '[${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${c.toString().padLeft(2, '0')}]';
    }

    return d.lines.map((l) => l.ms == null ? l.text : '${stamp(l.ms!)}${l.text}').join('\n');
  }

  Future<List<LyricHit>> search({String? custom}) async {
    final t = app.current;
    if (t == null || !lyricsNetOk) return const <LyricHit>[];
    final gen = _gen;
    busy = true;
    note = 'Searching everywhere…';
    notifyListeners();
    final r = await searchAll(t, custom);
    if (gen != _gen) return const <LyricHit>[];
    busy = false;
    hits = r;
    note = r.isEmpty ? 'Nothing found. Try your own words below.' : '';
    notifyListeners();
    return r;
  }

  String? applyHit(LyricHit h) {
    final t = app.current;
    if (t == null) return null;
    final d = buildLyrics(h.lrc);
    if (d == null) return 'Those lyrics are empty.';
    d.source = 'Found on ${h.source}';
    app.sp?.setString(_savedKey(t), h.lrc);
    _gen++;
    data = d;
    state = 'ready';
    note = '';
    notifyListeners();
    if (app.prefs.lyrTr) unawaited(translate());
    if (app.prefs.lyrRo) unawaited(romanize());
    return null;
  }

  Future<String> findOnline({bool quiet = false, String? custom}) async {
    final t = app.current;
    if (t == null) return '';
    if (!lyricsNetOk) return 'Online lyrics search is turned off in Settings → Privacy & online.';
    if (busy) return '';
    final gen = _gen;
    final r = await search(custom: custom);
    if (gen != _gen) return '';
    if (r.isEmpty) {
      return quiet ? '' : (note.isNotEmpty ? note : 'No lyrics found online');
    }
    final best = r.first;
    final err = applyHit(best);
    return quiet ? '' : (err ?? 'Lyrics found on ${best.source}${best.kind == 'word' ? ' (word by word)' : best.kind == 'line' ? ' (synced)' : ''}');
  }

  String _trKey(Track t) => 'athana_tr:${app.prefs.trLang}:${t.key}';
  String _roKey(Track t) => 'athana_ro:${t.key}';

  void _restoreExtras(Track t, LyricsData d) {
    final hash = _hash(d.lines.map((l) => l.text).join('\n'));
    try {
      final c = app.sp?.getString(_trKey(t));
      if (c != null) {
        final j = jsonDecode(c);
        if (j is Map && j['h'] == hash && j['tr'] is List && (j['tr'] as List).length == d.lines.length) {
          for (var i = 0; i < d.lines.length; i++) {
            final v = (j['tr'] as List)[i];
            if (d.lines[i].text.isNotEmpty && v is String) d.lines[i].tr = v;
          }
        }
      }
      final r = app.sp?.getString(_roKey(t));
      if (r != null) {
        final j = jsonDecode(r);
        if (j is Map && j['h'] == hash && j['ro'] is List && (j['ro'] as List).length == d.lines.length) {
          for (var i = 0; i < d.lines.length; i++) {
            final v = (j['ro'] as List)[i];
            if (v is String && v.isNotEmpty) d.lines[i].ro = v;
          }
        }
      }
    } catch (_) {}
  }

  void languageChanged() {
    final d = data;
    if (d != null) {
      for (final l in d.lines) {
        l.tr = null;
      }
      final t = app.current;
      if (t != null) _restoreExtras(t, d);
    }
    notifyListeners();
    if (app.prefs.lyrTr) unawaited(translate());
  }

  Future<String?> translate() async {
    final d = data, t = app.current;
    if (d == null || t == null) return null;
    if (!transNetOk) return 'Translation is turned off in Settings → Privacy & online.';
    final todo = <int>[for (var i = 0; i < d.lines.length; i++) if (d.lines[i].text.isNotEmpty && d.lines[i].tr == null) i];
    if (todo.isEmpty) return null;
    if (busy) return null;
    final gen = _gen;
    final lang = app.prefs.trLang;
    busy = true;
    note = 'Translating to $trName…';
    notifyListeners();
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
      if (gen != _gen || !app.prefs.lyrTr || lang != app.prefs.trLang) break;
      final ch = chunks[c];
      final texts = [for (final i in ch) d.lines[i].text.replaceAll(RegExp(r'\s*\n\s*'), ' ')];
      List<String?>? out;
      final r = await _gtx(texts.join('\n'), lang);
      if (r != null) {
        if (r.src == lang && c == 0) {
          for (final i in todo) {
            d.lines[i].tr = '';
          }
          msg = 'These lyrics are already in $trName.';
          break;
        }
        final parts = r.text.split('\n').map((s) => s.trim()).toList();
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
      }
      for (var k = 0; k < ch.length; k++) {
        final s = out[k];
        if (s == null) continue;
        final f = lang == 'id' ? casualId(s) : s;
        d.lines[ch[k]].tr = _trNorm(f) == _trNorm(texts[k]) ? '' : f;
        done++;
      }
      notifyListeners();
      if (done == 0) break;
    }
    if (gen == _gen) {
      busy = false;
      note = '';
      final all = d.lines.every((l) => l.text.isEmpty || l.tr != null);
      if (all) {
        app.sp?.setString(_trKey(t), jsonEncode({'h': _hash(d.lines.map((l) => l.text).join('\n')), 'tr': [for (final l in d.lines) l.tr ?? '']}));
      } else if (done == 0 && msg == null) {
        msg = 'Could not translate. Check your internet connection.';
      }
      notifyListeners();
    }
    return msg;
  }

  Future<String?> romanize() async {
    final d = data, t = app.current;
    if (d == null || t == null) return null;
    var own = 0, needNet = 0;
    final web = <int>[];
    for (var i = 0; i < d.lines.length; i++) {
      final text = d.lines[i].text;
      if (text.isEmpty || d.lines[i].ro != null) continue;
      final jp = hasJp(text);
      if (!jp && !hasHangul(text)) continue;
      if (jp && transNetOk) {
        web.add(i);
        continue;
      }
      final r = romanizeOffline(text);
      if (r != null && r.isNotEmpty) {
        d.lines[i].ro = r;
        own++;
      } else if (jp) {
        needNet++;
      }
    }
    if (own > 0) notifyListeners();
    var done = 0;
    if (web.isNotEmpty && !busy) {
      final gen = _gen;
      busy = true;
      note = 'Loading romaji…';
      notifyListeners();
      var next = 0;
      Future<void> worker() async {
        while (gen == _gen && app.prefs.lyrRo) {
          final k = next++;
          if (k >= web.length) return;
          final i = web[k];
          final r = await _gtx(d.lines[i].text, 'en', sl: 'ja', rm: true);
          var s = r?.translit.trim() ?? '';
          if (s.isEmpty && r == null) s = romanizeOffline(d.lines[i].text) ?? '';
          if (s.isNotEmpty) {
            d.lines[i].ro = s[0].toUpperCase() + s.substring(1);
            done++;
            if (done % 4 == 0) notifyListeners();
          } else if (r != null) {
            d.lines[i].ro = '';
          } else {
            needNet++;
          }
        }
      }

      await Future.wait([for (var w = 0; w < 4; w++) worker()]);
      if (gen != _gen) return null;
      busy = false;
      note = '';
    }
    if (done + own > 0) {
      app.sp?.setString(_roKey(t), jsonEncode({'h': _hash(d.lines.map((l) => l.text).join('\n')), 'ro': [for (final l in d.lines) l.ro ?? '']}));
    }
    notifyListeners();
    if (needNet > 0 && done + own == 0) {
      return transNetOk ? 'Romaji needs an internet connection for lines with kanji.' : 'Lines with kanji need the online service. Turn on "Translate lyrics online" in Settings → Privacy & online.';
    }
    return null;
  }

  String exportSaved() {
    final sp = app.sp;
    final items = <String, String>{};
    if (sp != null) {
      for (final k in sp.getKeys()) {
        if (!(k.startsWith('athana_lyr:') || k.startsWith('athana_tr:') || k.startsWith('athana_ro:'))) continue;
        final v = sp.get(k);
        if (v is String) items[k] = v;
      }
    }
    return jsonEncode({'athana': 'lyrics', 'v': 1, 'items': items});
  }

  int savedCount() {
    final sp = app.sp;
    if (sp == null) return 0;
    return sp.getKeys().where((String k) => k.startsWith('athana_lyr:') || k.startsWith('athana_tr:') || k.startsWith('athana_ro:')).length;
  }

  int importSaved(String text) {
    final sp = app.sp;
    if (sp == null) return -1;
    try {
      final j = jsonDecode(text.trim());
      if (j is! Map || j['athana'] != 'lyrics' || j['items'] is! Map) return -1;
      var n = 0;
      (j['items'] as Map).forEach((dynamic k, dynamic v) {
        if (k is String && v is String && (k.startsWith('athana_lyr:') || k.startsWith('athana_tr:') || k.startsWith('athana_ro:'))) {
          sp.setString(k, v);
          n++;
        }
      });
      return n;
    } catch (_) {
      return -1;
    }
  }

  int clearSaved() {
    final sp = app.sp;
    if (sp == null) return 0;
    var n = 0;
    for (final k in sp.getKeys().toList()) {
      if (k.startsWith('athana_lyr:') || k.startsWith('athana_tr:') || k.startsWith('athana_ro:')) {
        sp.remove(k);
        n++;
      }
    }
    return n;
  }
}
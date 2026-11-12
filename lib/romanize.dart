// Athana's own romaji: Japanese kana and Korean hangul read in Latin letters, with no internet and no outside service.
// (Kanji need a dictionary, so lines with kanji still use the online service when it is allowed.)

const Map<String, String> _base = {"あ": "a", "い": "i", "う": "u", "え": "e", "お": "o", "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko", "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so", "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to", "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no", "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho", "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo", "や": "ya", "ゆ": "yu", "よ": "yo", "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro", "わ": "wa", "ゐ": "i", "ゑ": "e", "を": "o", "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go", "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo", "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do", "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo", "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po", "ゔ": "vu"};
const Map<String, String> _small = {"ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o", "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ゎ": "wa"};
const Map<String, String> _combo = {"きゃ": "kya", "きゅ": "kyu", "きょ": "kyo", "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo", "しゃ": "sha", "しゅ": "shu", "しょ": "sho", "しぇ": "she", "じゃ": "ja", "じゅ": "ju", "じょ": "jo", "じぇ": "je", "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho", "ちぇ": "che", "ぢゃ": "ja", "ぢゅ": "ju", "ぢょ": "jo", "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo", "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo", "びゃ": "bya", "びゅ": "byu", "びょ": "byo", "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo", "みゃ": "mya", "みゅ": "myu", "みょ": "myo", "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo", "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu", "てぃ": "ti", "てゅ": "tyu", "でぃ": "di", "でゅ": "dyu", "とぅ": "tu", "どぅ": "du", "うぃ": "wi", "うぇ": "we", "うぉ": "wo", "つぁ": "tsa", "つぃ": "tsi", "つぇ": "tse", "つぉ": "tso", "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo", "いぇ": "ye", "くぁ": "kwa", "くぃ": "kwi", "くぇ": "kwe", "くぉ": "kwo", "ぐぁ": "gwa", "すぃ": "si", "ずぃ": "zi"};
const Map<String, String> _punct = {"、": ",", "。": ".", "！": "!", "？": "?", "・": " ", "「": "\"", "」": "\"", "『": "\"", "』": "\"", "〜": "~", "　": " ", "（": "(", "）": ")"};
const Map<String, String> _words = {"こんにちは": "konnichiwa", "こんばんは": "konbanwa"};
const List<String> _hgL = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"];
const List<String> _hgV = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"];
const List<int> _hgCarry = [-1, 0, 1, 9, 2, 12, -1, 3, 5, 0, 6, 7, 9, 16, 17, -1, 6, 7, 9, 9, 10, -1, 12, 14, 15, 16, 17, -1];
const List<String> _hgStay = ["", "", "", "k", "", "n", "n", "", "", "l", "l", "l", "l", "l", "l", "l", "", "", "p", "", "", "ng", "", "", "", "", "", ""];
const List<String> _hgRep = ["", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "l", "l", "l", "p", "l", "m", "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "t"];

// ------------------------------------------------------------------------- Japanese kana → Hepburn
String _hira(int u) => (u >= 0x30A1 && u <= 0x30F6) ? String.fromCharCode(u - 0x60) : String.fromCharCode(u);

String _dbl(String r) {
  if (r.startsWith('ch')) return 't$r';
  if ('aiueo'.contains(r[0])) return r;
  return r[0] + r;
}

String _kana(String text) {
  final cs = <String>[for (final u in text.codeUnits) _hira(u)];
  final n = cs.length;
  final out = <String>[];
  var gem = false;
  var i = 0;
  void emit(String r) {
    var x = r;
    if (gem && x.isNotEmpty) x = _dbl(x);
    gem = false;
    out.add(x);
  }

  while (i < n) {
    final c = cs[i];
    String? wk;
    for (final k in _words.keys) {
      if (i + k.length <= n && cs.sublist(i, i + k.length).join() == k) {
        wk = k;
        break;
      }
    }
    if (wk != null) {
      emit(_words[wk]!);
      i += wk.length;
      continue;
    }
    final pair = i + 1 < n ? c + cs[i + 1] : '';
    if (pair.isNotEmpty && _combo.containsKey(pair)) {
      emit(_combo[pair]!);
      i += 2;
      continue;
    }
    if (pair.isNotEmpty && _base.containsKey(c) && _base[c]!.endsWith('i') && 'ゃゅょ'.contains(cs[i + 1])) {
      final b = _base[c]!;
      final st = (b == 'shi' || b == 'chi' || b == 'ji') ? b.substring(0, b.length - 1) : '${b.substring(0, b.length - 1)}y';
      final sm = _small[cs[i + 1]]!;
      emit(st + sm.substring(sm.length - 1));
      i += 2;
      continue;
    }
    if (c == 'っ') {
      gem = true;
      i++;
      continue;
    }
    if (c == 'ん') {
      final nx = i + 1 < n ? cs[i + 1] : '';
      emit(nx.isNotEmpty && 'あいうえおやゆよ'.contains(nx) ? "n'" : 'n');
      i++;
      continue;
    }
    if (c == 'ー') {
      final j = out.join();
      final last = j.isEmpty ? '' : j.substring(j.length - 1);
      if (last.isNotEmpty && 'aiueo'.contains(last)) out.add(last);
      i++;
      continue;
    }
    if (c == 'は' || c == 'へ') {
      // は and へ are read "wa" and "e" when they stand on their own between spaces (the particles).
      final prevOk = i == 0 || ' 　,、'.contains(cs[i - 1]);
      final nextOk = i + 1 >= n || ' 　,、。.!?！？'.contains(cs[i + 1]);
      if (prevOk && nextOk) {
        emit(c == 'は' ? 'wa' : 'e');
        i++;
        continue;
      }
    }
    final b = _base[c];
    if (b != null) {
      emit(b);
      i++;
      continue;
    }
    final s = _small[c];
    if (s != null) {
      emit(s);
      i++;
      continue;
    }
    final p = _punct[c];
    if (p != null) {
      emit(p);
      i++;
      continue;
    }
    emit(c);
    i++;
  }
  return out.join();
}

// ------------------------------------------------------------------------- Korean hangul → Revised Romanization
class _Syl {
  final bool hangul;
  final String ch;
  final int l, v, t;
  const _Syl(this.hangul, this.ch, this.l, this.v, this.t);
}

String _hangul(String text) {
  final syl = <_Syl>[];
  for (final u in text.codeUnits) {
    if (u >= 0xAC00 && u <= 0xD7A3) {
      final x = u - 0xAC00;
      syl.add(_Syl(true, '', x ~/ 588, (x % 588) ~/ 28, x % 28));
    } else {
      syl.add(_Syl(false, String.fromCharCode(u), 0, 0, 0));
    }
  }
  final out = StringBuffer();
  final over = <int, String>{}; // an initial that a sound change has replaced
  for (var idx = 0; idx < syl.length; idx++) {
    final s = syl[idx];
    if (!s.hangul) {
      out.write(s.ch);
      continue;
    }
    final ini = over.remove(idx) ?? _hgL[s.l];
    var fin = '';
    final t = s.t;
    final nxt = idx + 1 < syl.length && syl[idx + 1].hangul ? syl[idx + 1] : null;
    if (t != 0) {
      if (nxt != null) {
        final nl = nxt.l;
        if (nl == 11) {
          // The next syllable starts with a silent ㅇ, so the final sound moves over to it.
          if ((t == 7 || t == 25) && nxt.v == 20) {
            over[idx + 1] = t == 7 ? 'j' : 'ch'; // 같이 → gachi
          } else if (t == 27) {
            fin = '';
          } else if (t == 21) {
            fin = 'ng';
          } else {
            fin = _hgStay[t];
            final c = _hgCarry[t];
            if (c >= 0) over[idx + 1] = _hgL[c];
          }
        } else {
          var rep = _hgRep[t];
          if (t == 27 && (nl == 0 || nl == 3 || nl == 12)) {
            fin = '';
            over[idx + 1] = nl == 0 ? 'k' : nl == 3 ? 't' : 'ch';
          } else if ((rep == 'k' || rep == 't' || rep == 'p') && nl == 18) {
            fin = '';
            over[idx + 1] = rep;
          } else {
            if ((rep == 'k' || rep == 't' || rep == 'p') && (nl == 2 || nl == 6 || nl == 5)) {
              rep = rep == 'k' ? 'ng' : rep == 't' ? 'n' : 'm';
              if (nl == 5) over[idx + 1] = 'n';
            } else if (rep == 'n' && nl == 5) {
              rep = 'l';
              over[idx + 1] = 'l';
            } else if (rep == 'l' && nl == 2) {
              over[idx + 1] = 'l';
            } else if ((rep == 'm' || rep == 'ng') && nl == 5) {
              over[idx + 1] = 'n';
            }
            fin = rep;
          }
        }
      } else {
        fin = _hgRep[t];
      }
    }
    out.write(ini + _hgV[s.v] + fin);
  }
  return out.toString();
}

// ------------------------------------------------------------------------- the entry points
bool _isKana(int u) => u >= 0x3040 && u <= 0x30FF;
bool _isHangul(int u) => u >= 0xAC00 && u <= 0xD7A3;

/// True when the text has hangul (Korean).
bool hasHangul(String s) => s.codeUnits.any(_isHangul);

/// True when the text has kanji or hanzi, which need a dictionary to read.
bool hasIdeograph(String s) => s.codeUnits.any((int u) => u >= 0x4E00 && u <= 0x9FFF);

/// Reads one lyric line in Latin letters with no internet: Japanese kana (Hepburn) and Korean hangul (Revised Romanization).
/// Returns null when the line has kanji or hanzi (they need a dictionary), or has no kana or hangul at all.
String? romanizeOffline(String text) {
  if (hasIdeograph(text)) return null;
  final cu = text.codeUnits;
  if (!cu.any((int u) => _isKana(u) || _isHangul(u))) return null;
  final parts = StringBuffer();
  final run = StringBuffer();
  var mode = '';
  void flush() {
    if (run.isEmpty) return;
    parts.write(mode == 'h' ? _hangul(run.toString()) : _kana(run.toString()));
    run.clear();
    mode = '';
  }

  for (final u in cu) {
    final m = _isHangul(u) ? 'h' : 'k';
    if (mode.isNotEmpty && m != mode) flush();
    mode = m;
    run.writeCharCode(u);
  }
  flush();
  final s = parts.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

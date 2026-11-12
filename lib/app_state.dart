import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:shared_preferences/shared_preferences.dart';

import 'design.dart';
import 'eq_presets.dart';
import 'lyrics.dart';
import 'models.dart';
import 'native.dart';

const String kVersion = '2.1.3';
const List<int> kAccents = [0xFF9682FF, 0xFFFF6996, 0xFF46AAFF, 0xFF3CD7AA, 0xFFFFAA3C, 0xFFEB4646];
const List<String> kAccentNames = ['Violet', 'Rose', 'Ocean', 'Mint', 'Amber', 'Crimson'];

int _i(dynamic v, int d) => v is int ? v : d;
bool _b(dynamic v, bool d) => v is bool ? v : d;

/// Every option in Settings. Each one is read where it takes effect.
class Prefs {
  int accent = 0, textScale = 100;
  bool compact = false, showMeta = true;
  int skipSec = 10, prevRestart = 3;
  bool autoplay = false, remRepeat = true, remShuffle = false, sleepFinish = false;
  int repeatSaved = 0;
  bool shuffleSaved = false;
  bool remain = false, swipe = true, haptic = false, cleanNum = true;


  int dataUsage = 1; // 0 = Low, 1 = Normal, 2 = High
  int networkMode = 1; // 0 = Always Allow, 1 = Ask, 2 = Wi-Fi Only

  // Controls
  bool swipeRev = false, awake = false, kbd = true;
  int sleepFade = 10;
  int fadeSec = 0;
  bool cloudMeta = false;
  String offlineMode = 'played';
  int offlineLimitGb = 3;
  bool autoRefresh = true;
  bool offlineWifi = true;
  bool hiresCheck = true;
  bool warmNext = true;
  String dblTap = 'playpause';
  String lpress = 'more';
  String hs1 = 'playpause', hs2 = 'next', hs3 = 'prev';
  bool unplugPause = true, plugPlay = false;
  bool eqOn = false, eqAuto = true;
  double eqPre = 0;
  String bgMode = 'ambient';
  int glow = 100;
  String wallPath = '';
  int wallBlur = 0;
  int wallDim = 35;
  bool lite = false, calm = false, focus = false;
  double lyrSize = 1.0;
  bool lyrCenter = true, lyrSoft = true, lyrTr = false, lyrRo = false, lrcAuto = false;
  String trLang = 'id';
  bool offline = false, netLyrics = true, netTranslate = true, netUpdates = true, netTags = true;
  int lastUpdateCheck = 0;
  String skipVersion = '';
  int supportFirst = 0, supportOpens = 0, supportAsked = 0, supportLast = 0;
  bool supportNever = false;
  List<double> eqGains = List<double>.filled(10, 0.0);
  String eqPreset = 'Flat';
  List<double> eqBase = List<double>.filled(10, 0.0);
  double eqStrength = 100;
  double mixBal = 0;
  int mixWide = 0;
  bool mixMono = false;
  int mixVol = 100;
  int mixCross = 0;
  bool autoOut = false;
  Map<String, List<double>> myEq = <String, List<double>>{};
  bool rgOn = false;
  int rgTarget = -18;

  Map<String, dynamic> toJson() => {
    'accent': accent,
    'textScale': textScale,
    'compact': compact,
    'showMeta': showMeta,
    'skipSec': skipSec,
    'prevRestart': prevRestart,
    'autoplay': autoplay,
    'remRepeat': remRepeat,
    'remShuffle': remShuffle,
    'sleepFinish': sleepFinish,
    'repeatSaved': repeatSaved,
    'shuffleSaved': shuffleSaved,
    'remain': remain,
    'swipe': swipe,
    'haptic': haptic,
    'swipeRev': swipeRev,
    'awake': awake,
    'cloudMeta': cloudMeta,
    'offlineMode': offlineMode,
    'offlineLimitGb': offlineLimitGb,
    'autoRefresh': autoRefresh,
    'offlineWifi': offlineWifi,
    'warmNext': warmNext,
    'hiresCheck': hiresCheck,
    'fadeSec': fadeSec,
    'sleepFade': sleepFade,
    'kbd': kbd,
    'dblTap': dblTap,
    'lpress': lpress,
    'hs1': hs1,
    'hs2': hs2,
    'hs3': hs3,
    'unplugPause': unplugPause,
    'plugPlay': plugPlay,
    'cleanNum': cleanNum,
    'eqOn': eqOn,
    'eqAuto': eqAuto,
    'eqPre': eqPre,
    'eqGains': eqGains,
    'eqPreset': eqPreset,
    'eqBase': eqBase,
    'eqStrength': eqStrength,
    'mixBal': mixBal,
    'mixWide': mixWide,
    'mixMono': mixMono,
    'mixVol': mixVol,
    'mixCross': mixCross,
    'autoOut': autoOut,
    'myEq': myEq,
    'bgMode': bgMode,
    'glow': glow,
    'wallPath': wallPath,
    'wallBlur': wallBlur,
    'wallDim': wallDim,
    'lite': lite,
    'calm': calm,
    'focus': focus,
    'lyrSize': lyrSize,
    'lyrCenter': lyrCenter,
    'lyrSoft': lyrSoft,
    'lyrTr': lyrTr,
    'lyrRo': lyrRo,
    'lrcAuto': lrcAuto,
    'trLang': trLang,
    'offline': offline,
    'netLyrics': netLyrics,
    'netTranslate': netTranslate,
    'netUpdates': netUpdates,
    'netTags': netTags,
    'lastUpdateCheck': lastUpdateCheck,
    'skipVersion': skipVersion,
    'supportFirst': supportFirst,
    'supportOpens': supportOpens,
    'supportAsked': supportAsked,
    'supportLast': supportLast,
    'supportNever': supportNever,
    'rgOn': rgOn,
    'rgTarget': rgTarget,
    'dataUsage': dataUsage,
    'networkMode': networkMode,
  };

  void load(Map<String, dynamic> j) {
    accent = _i(j['accent'], accent).clamp(0, kAccents.length - 1).toInt();
    textScale = _i(j['textScale'], textScale).clamp(85, 130).toInt();
    compact = _b(j['compact'], compact);
    showMeta = _b(j['showMeta'], showMeta);
    skipSec = _i(j['skipSec'], skipSec);
    prevRestart = _i(j['prevRestart'], prevRestart);
    autoplay = _b(j['autoplay'], autoplay);
    remRepeat = _b(j['remRepeat'], remRepeat);
    remShuffle = _b(j['remShuffle'], remShuffle);
    sleepFinish = _b(j['sleepFinish'], sleepFinish);
    repeatSaved = _i(j['repeatSaved'], repeatSaved).clamp(0, 2).toInt();
    shuffleSaved = _b(j['shuffleSaved'], shuffleSaved);
    remain = _b(j['remain'], remain);
    swipe = _b(j['swipe'], swipe);
    haptic = _b(j['haptic'], haptic);
    swipeRev = _b(j['swipeRev'], swipeRev);
    awake = _b(j['awake'], awake);
    cloudMeta = _b(j['cloudMeta'], cloudMeta);
    final om = j['offlineMode'];
    offlineMode = (om == 'played' || om == 'all' || om == 'off') ? om as String : (_b(j['offlineAuto'], true) ? 'played' : 'off');
    offlineLimitGb = _i(j['offlineLimitGb'], 3).clamp(0, 100).toInt();
    autoRefresh = _b(j['autoRefresh'], autoRefresh);
    offlineWifi = _b(j['offlineWifi'], offlineWifi);
    warmNext = _b(j['warmNext'], warmNext);
    hiresCheck = _b(j['hiresCheck'], hiresCheck);
    fadeSec = _i(j['fadeSec'], 0).clamp(0, 10).toInt();
    sleepFade = _i(j['sleepFade'], 10).clamp(0, 60).toInt();
    kbd = _b(j['kbd'], kbd);
    final dt = j['dblTap'];
    dblTap = (dt == 'off' || dt == 'next' || dt == 'prev') ? dt as String : 'playpause';
    final lp = j['lpress'];
    lpress = (lp == 'off' || lp == 'signal' || lp == 'lyrics') ? lp as String : 'more';
    String hs(dynamic v, String d) => (v is String && const ['playpause', 'next', 'prev', 'skipback', 'skipfwd', 'off'].contains(v)) ? v : d;
    hs1 = hs(j['hs1'], 'playpause');
    hs2 = hs(j['hs2'], 'next');
    hs3 = hs(j['hs3'], 'prev');
    unplugPause = _b(j['unplugPause'], unplugPause);
    plugPlay = _b(j['plugPlay'], plugPlay);
    cleanNum = _b(j['cleanNum'], cleanNum);
    eqOn = _b(j['eqOn'], eqOn);
    eqAuto = _b(j['eqAuto'], eqAuto);
    final pre = j['eqPre'];
    eqPre = pre is num ? pre.toDouble().clamp(-12.0, 12.0).toDouble() : 0.0;
    eqGains = _gains(j['eqGains']) ?? List<double>.filled(10, 0.0);
    eqBase = _gains(j['eqBase']) ?? List<double>.of(eqGains);
    final st = j['eqStrength'];
    final mb = j['mixBal'];
    mixBal = mb is num ? mb.toDouble().clamp(-1.0, 1.0).toDouble() : 0.0;
    mixWide = _i(j['mixWide'], 0).clamp(0, 100).toInt();
    mixMono = _b(j['mixMono'], false);
    mixVol = _i(j['mixVol'], 100).clamp(0, 150).toInt();
    mixCross = _i(j['mixCross'], 0).clamp(0, 100).toInt();
    autoOut = _b(j['autoOut'], false);
    eqStrength = st is num ? st.toDouble().clamp(50.0, 200.0).toDouble() : 100.0;
    final name = j['eqPreset'];
    eqPreset = name is String ? name : 'Flat';
    final my = <String, List<double>>{};
    final raw = j['myEq'];
    if (raw is Map) {
      raw.forEach((dynamic k, dynamic v) {
        final g = _gains(v);
        if (g != null) my[k.toString()] = g;
      });
    }
    myEq = my;
    final bm = j['bgMode'];
    bgMode = (bm == 'aurora' || bm == 'minimal') ? bm as String : 'ambient';
    glow = _i(j['glow'], 100).clamp(0, 100);
    final wp = j['wallPath'];
    wallPath = wp is String ? wp : '';
    wallBlur = _i(j['wallBlur'], 0).clamp(0, 40);
    wallDim = _i(j['wallDim'], 35).clamp(0, 90);
    lite = _b(j['lite'], lite);
    calm = _b(j['calm'], calm);
    focus = _b(j['focus'], focus);
    final ls = j['lyrSize'];
    lyrSize = ls is num ? ls.toDouble().clamp(0.8, 1.6).toDouble() : 1.0;
    lyrCenter = _b(j['lyrCenter'], lyrCenter);
    lyrSoft = _b(j['lyrSoft'], lyrSoft);
    lyrTr = _b(j['lyrTr'], lyrTr);
    lyrRo = _b(j['lyrRo'], lyrRo);
    lrcAuto = _b(j['lrcAuto'], lrcAuto);
    final tl = j['trLang'];
    trLang = (tl is String && kTrLangs.containsKey(tl)) ? tl : 'id';
    offline = _b(j['offline'], offline);
    netLyrics = _b(j['netLyrics'], netLyrics);
    netTranslate = _b(j['netTranslate'], netTranslate);
    netUpdates = _b(j['netUpdates'], netUpdates);
    netTags = _b(j['netTags'], netTags);
    lastUpdateCheck = _i(j['lastUpdateCheck'], 0);
    final sv = j['skipVersion'];
    skipVersion = sv is String ? sv : '';
    supportFirst = _i(j['supportFirst'], 0);
    supportOpens = _i(j['supportOpens'], 0);
    supportAsked = _i(j['supportAsked'], 0);
    supportLast = _i(j['supportLast'], 0);
    supportNever = _b(j['supportNever'], false);
    rgOn = _b(j['rgOn'], rgOn);
    final rt = j['rgTarget'];
    rgTarget = (rt is num && (rt == -23 || rt == -18 || rt == -14)) ? rt.toInt() : -18;

    dataUsage = _i(j['dataUsage'], 1).clamp(0, 2).toInt();
    networkMode = _i(j['networkMode'], 1).clamp(0, 2).toInt();
  }

  static List<double>? _gains(dynamic v) {
    if (v is! List || v.length != 10) return null;
    return [for (final e in v) e is num ? e.toDouble().clamp(-12.0, 12.0).toDouble() : 0.0];
  }
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final Prefs prefs = Prefs();
  List<Track> library = <Track>[];
  List<Track> queue = <Track>[];
  List<LinkedFolder> folders = <LinkedFolder>[];
  List<Playlist> playlists = <Playlist>[];
  int _countedTok = -1;

  int index = -1;
  bool playing = false, busy = false;
  int durationMs = 0;
  final ValueNotifier<int> positionMs = ValueNotifier<int>(0);
  bool shuffle = false;
  int repeat = 0; // 0 off, 1 all, 2 one
  double speed = 1.0;
  String format = '';
  int infoRate = 0, infoOut = 0; // sample rate of the song and of the device output (for the signal path)
  String infoMime = '';
  bool infoOwn = false; // the song is being decoded by Athana's own FLAC decoder
  bool infoBp = false; // Android's bit-perfect mixer is in use (the song reaches a USB DAC with no mixing or resampling)
  int infoOwnOut = 0; // bit depth Athana's own audio output is delivering to the device (0 = the standard output is used)
  String? error;
  // The Hi-Res check of the playing song: '' (not a Hi-Res file or switched off), 'wait', 'analysing', 'done' or 'failed'.
  String hrState = '';
  Map<String, dynamic>? hrResult;
  String hrWhy = ''; // why the check failed, for the card
  final Set<String> _hrRetry = <String>{}; // songs whose check was cancelled and already tried again once
  bool _hrBusy = false;
  int _hrRunId = 0;
  Timer? _hrTimer;
  String normStatus = ''; // '', 'measuring', 'ready' or 'failed' (loudness normalisation, current song)
  double normGain = 0;
  int sleepMinutes = 0;
  bool stopAfter = false;
  String? message; // one-line status shown by the screens

  List<Track> _base = <Track>[];
  bool _baseAll = true, _loaded = false, _metaRunning = false;
  int _tok = 0;
  Timer? _sleep;
  SharedPreferences? _sp;
  SharedPreferences? get sp => _sp;
  late final LyricsController lyr = LyricsController(this);
  StreamSubscription<Map<String, dynamic>>? _sub;
  List<Track>? _sortedCache;

  Track? get current => (index >= 0 && index < queue.length) ? queue[index] : null;

  List<Track> get songsSorted {
    return _sortedCache ??= (List<Track>.of(library)..sort((a, b) => naturalCompare(a.title, b.title)));
  }

  // ---------------------------------------------------------------- start
  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    _sp = sp;
    try {
      final s = sp.getString('athana_set');
      if (s != null) prefs.load(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {}
    try {
      final l = sp.getString('athana_lib');
      if (l != null) {
        library = (jsonDecode(l) as List).map((dynamic e) => Track.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      }
    } catch (_) {}
    try {
      final f = sp.getString('athana_folders');
      if (f != null) {
        folders = (jsonDecode(f) as List).map((dynamic e) => LinkedFolder.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      }
    } catch (_) {}
    // Songs and folders from an earlier test build that could read a server address are dropped; Athana reads phone and Google Drive songs only.
    library.removeWhere((Track t) => t.uri.startsWith('http://') || t.uri.startsWith('https://'));
    folders.removeWhere((LinkedFolder f) => f.uri.startsWith('http://') || f.uri.startsWith('https://'));
    // Version 3 of the song reader adds genre, year, composer, album artist, quality and AIFF/WAV tags, so read every song once more.
    // Version 4 reads the sample rate and bit depth of FLAC songs on Android 11 and older.
    if ((sp.getInt('athana_metav') ?? 0) < 4) {
      for (final t in library) {
        t.metaDone = false;
      }
      await sp.setInt('athana_metav', 4);
    }
    try {
      final pl = sp.getString('athana_pl');
      if (pl != null) playlists = (jsonDecode(pl) as List).map((dynamic e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {}
    _base = List<Track>.of(library);
    queue = List<Track>.of(library);
    if (prefs.remRepeat) repeat = prefs.repeatSaved;
    if (prefs.remShuffle && prefs.shuffleSaved && queue.isNotEmpty) {
      shuffle = true;
      queue.shuffle();
    }
    if (queue.isNotEmpty) index = 0;
    _sub = Native.events.listen(_onEvent, onError: (Object _) {});
    if (prefs.wallPath.isNotEmpty && !File(prefs.wallPath).existsSync()) prefs.wallPath = ''; // the picture is gone
    _syncLook();
    addListener(_syncAwake);
    _syncHeadset();
    _syncFade();
    if (prefs.eqOn) eqApply();
    if (!mixIsDefault) mixApply();
    _loadOutProfiles();
    Native.output().then((Map<String, String> o) => onOutput(o['kind'] ?? 'speaker', o['name'] ?? '')).catchError((Object _) {});
    if (prefs.rgOn) normApply();
    _loadMeta();
    offlineRefresh();
    if (prefs.offlineMode == 'all' && library.any((Track t) => t.cloud)) unawaited(offlineSync()); // carries on with songs that are not saved yet
    unawaited(offlineTrim()); // keeps the saved songs within the limit
    WidgetsBinding.instance.addObserver(this);
    // The library is already on screen from the last session. A few seconds later, look for songs that were added or that came back.
    Future<void>.delayed(const Duration(seconds: 4), () => quietRefresh(force: true));
  }

  // ---------------------------------------------------------------- coming back to your folders
  /// Folders that Android stopped remembering. The Library offers to reconnect them.
  Set<String> lostTrees = <String>{};
  bool _quiet = false;
  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);

  /// Quietly checks every linked folder, one at a time. New songs and songs that returned appear by themselves; nothing is removed.
  Future<void> quietRefresh({bool force = false}) async {
    if (folders.isEmpty || _quiet || busy) return;
    if (!force && DateTime.now().difference(_lastScan) < const Duration(minutes: 10)) return;
    _quiet = true;
    try {
      var ok = <String>{};
      try {
        ok = await Native.treeAccess();
      } catch (_) {}
      final lost = <String>{};
      for (final f in List<LinkedFolder>.of(folders)) {
        if (!ok.contains(f.uri)) {
          lost.add(f.uri);
          continue;
        }
        if (!prefs.autoRefresh) continue;
        final r = await Native.scanTree(f.uri);
        if (r == null) {
          lost.add(f.uri);
          continue;
        }
        await addSongs(r, tree: f.uri);
        await Future<void>.delayed(const Duration(milliseconds: 300)); // gentle: one folder at a time
      }
      lostTrees = lost;
      _lastScan = DateTime.now();
      notifyListeners();
    } catch (_) {
    } finally {
      _quiet = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(quietRefresh()); // at most every 10 minutes
      unawaited(offlineResume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    removeListener(_syncAwake);
    _sub?.cancel();
    _sleep?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- saving
  void _saveLib() {
    try {
      _sp?.setString('athana_lib', jsonEncode(library.map((t) => t.toJson()).toList()));
      _sp?.setString('athana_folders', jsonEncode(folders.map((f) => f.toJson()).toList()));
    } catch (_) {}
  }

  void savePrefs() {
    try {
      _sp?.setString('athana_set', jsonEncode(prefs.toJson()));
    } catch (_) {}
    _syncLook();
    _syncHeadset();
    _syncFade();
    _storeOut();
    notifyListeners();
  }

  int _fadeSent = -1;
  void _syncFade() {
    if (prefs.fadeSec == _fadeSent) return;
    _fadeSent = prefs.fadeSec;
    Native.fadeSet(prefs.fadeSec).catchError((_) {});
  }

  // ---------------------------------------------------------------- A–B loop
  int loopA = -1, loopB = -1; // milliseconds, -1 = not set

  /// One button: the first press sets A, the second sets B (the section then repeats), the third clears the loop.
  /// Returns a short message.
  String loopStep() {
    final pos = positionMs.value;
    String msg;
    if (loopA < 0) {
      loopA = pos;
      msg = 'Loop start set. Press again for the end.';
    } else if (loopB < 0) {
      if (pos <= loopA + 500) return 'Play a little further, then set the end.';
      loopB = pos;
      msg = 'Looping this section';
    } else {
      loopA = -1;
      loopB = -1;
      msg = 'Loop cleared';
    }
    Native.loopSet(loopA, loopB).catchError((_) {});
    notifyListeners();
    return msg;
  }

  void loopSetA() {
    loopA = positionMs.value;
    if (loopB >= 0 && loopB <= loopA + 500) loopB = -1;
    Native.loopSet(loopA, loopB).catchError((_) {});
    notifyListeners();
  }

  void loopSetB() {
    if (loopA < 0 || positionMs.value <= loopA + 500) return;
    loopB = positionMs.value;
    Native.loopSet(loopA, loopB).catchError((_) {});
    notifyListeners();
  }

  void loopClear() {
    if (loopA < 0 && loopB < 0) return;
    loopA = -1;
    loopB = -1;
    Native.loopSet(-1, -1).catchError((_) {});
    notifyListeners();
  }

  String _hsKey = '';
  /// Tells the player what the headphone button and unplugging should do.
  void _syncHeadset() {
    final k = '${prefs.hs1}|${prefs.hs2}|${prefs.hs3}|${prefs.unplugPause}';
    if (k == _hsKey) return;
    _hsKey = k;
    Native.headset(prefs.hs1, prefs.hs2, prefs.hs3, prefs.unplugPause).catchError((_) {});
  }

  bool _awakeOn = false;
  /// Keeps the screen on while a song plays, when the option is on. Runs on every change.
  void _syncAwake() {
    final want = prefs.awake && playing;
    if (want == _awakeOn) return;
    _awakeOn = want;
    Native.keepAwake(want).catchError((_) {});
  }

  /// Hands the background settings to the page backgrounds.
  void _syncLook() {
    kLook.value = Look(
      bg: prefs.bgMode,
      glow: prefs.glow / 100,
      wall: prefs.wallPath.isEmpty ? null : prefs.wallPath,
      wallBlur: prefs.wallBlur.toDouble(),
      wallDim: prefs.wallDim / 100,
      lite: prefs.lite,
      calm: prefs.calm,
    );
  }

  /// Lets the user pick a picture for the background. Returns a message for a toast.
  Future<String?> pickWallpaper() async {
    try {
      final path = await Native.pickImage();
      if (path == null) return null;
      prefs.wallPath = path;
      savePrefs();
      return 'Wallpaper applied';
    } on PlatformException {
      return 'Could not read that image';
    }
  }

  void removeWallpaper() {
    final old = prefs.wallPath;
    prefs.wallPath = '';
    savePrefs();
    if (old.isNotEmpty) {
      try {
        File(old).deleteSync();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- your own titles and artists
  /// Gives one song your own title and artist. An empty box, or the same text as the file, goes back to the file's.
  void editSong(Track t, String title, String artist) {
    final nt = title.trim(), na = artist.trim();
    t.editTitle = (nt.isNotEmpty && nt != t.baseTitle) ? nt : '';
    t.editArtist = (na.isNotEmpty && na != t.baseArtist) ? na : '';
    t.refreshEdits();
    _afterEdit();
  }

  /// Applies what was found online to one song. Everything stays on this phone; the file is not changed. Null parts are left alone.
  Future<String> applyOnline(Track t, {String? title, String? artist, String? album, String? year, Uint8List? cover}) async {
    String? path;
    if (cover != null) {
      try {
        path = await Native.saveCoverBytes(cover);
      } catch (_) {}
    }
    if (title != null && title.trim().isNotEmpty) t.editTitle = title.trim() != t.baseTitle ? title.trim() : '';
    if (artist != null && artist.trim().isNotEmpty) t.editArtist = artist.trim() != t.baseArtist ? artist.trim() : '';
    if (album != null && album.trim().isNotEmpty) t.editAlbum = album.trim() != t.baseAlbum ? album.trim() : '';
    if (year != null && year.trim().isNotEmpty) t.editYear = year.trim() != t.baseYear ? year.trim() : '';
    var coverNote = '';
    if (cover != null) {
      if (path != null && path.isNotEmpty) {
        final old = <String>{if (t.editArt.isNotEmpty) t.editArt};
        t.editArt = path;
        t.refreshEdits();
        _dropUnusedCovers(old);
      } else {
        coverNote = ' The cover could not be read.';
      }
    }
    t.refreshEdits();
    _afterEdit();
    if (identical(current, t)) unawaited(Native.updateInfo(t).catchError((Object _) {}));
    return 'Saved.$coverNote';
  }

  void resetSongEdit(Track t) {
    t.editTitle = '';
    t.editArtist = '';
    t.editAlbum = '';
    t.editYear = '';
    t.refreshEdits();
    _afterEdit();
  }

  /// One artist name for every song of an artist or album. An empty name restores the artists from the files.
  void editArtistOf(List<Track> list, String name) {
    final na = name.trim();
    for (final t in List<Track>.of(list)) {
      t.editArtist = (na.isNotEmpty && na != t.baseArtist) ? na : '';
      t.refreshEdits();
    }
    _afterEdit();
  }

  /// Lets you pick a picture from the phone as the cover of these songs. Returns a short message, or null when you cancelled.
  Future<String?> changeCover(List<Track> list) async {
    if (list.isEmpty) return null;
    try {
      final path = await Native.pickImage(cover: true);
      if (path == null) return null;
      final old = <String>{for (final t in list) if (t.editArt.isNotEmpty) t.editArt};
      for (final t in list) {
        t.editArt = path;
        t.refreshEdits();
      }
      _dropUnusedCovers(old);
      _afterEdit();
      return list.length == 1 ? 'Cover changed' : 'Cover changed for ${list.length} songs';
    } on PlatformException {
      return 'Could not read that picture';
    }
  }

  /// Goes back to the cover inside the file.
  void resetCover(List<Track> list) {
    final old = <String>{for (final t in list) if (t.editArt.isNotEmpty) t.editArt};
    for (final t in list) {
      t.editArt = '';
      t.refreshEdits();
    }
    _dropUnusedCovers(old);
    _afterEdit();
  }

  /// Deletes picture files that no song uses any more.
  void _dropUnusedCovers(Set<String> files) {
    for (final f in files) {
      if (library.any((Track t) => t.editArt == f)) continue;
      try {
        File(f).deleteSync();
      } catch (_) {}
    }
  }

  void _afterEdit() {
    _invalidate();
    _saveLib();
    notifyListeners();
  }

  // ---------------------------------------------------------------- library
  void _invalidate() => _sortedCache = null;

  int lastRelinked = 0; // how many songs of the last addSongs call got a fresh Google Drive link

  /// Adds songs that are not in the library yet. Returns how many were new.
  Future<int> addSongs(List<Map<String, dynamic>> raw, {String tree = ''}) async {
    final byKey = <String, Track>{for (final t in library) t.key: t};
    final have = <String>{...byKey.keys};
    final fresh = <Track>[];
    lastRelinked = 0;
    for (final m in raw) {
      final t = Track.fromScan(m, clean: prefs.cleanNum, tree: tree);
      if (t.uri.isEmpty) continue;
      final old = byKey[t.key];
      if (old != null) {
        // The same song picked again from Google Drive: keep the entry (plays, playlists, edits) and give it the fresh link,
        // because the old one may have lost Android's permission.
        if (old.cloud && t.cloud && old.uri != t.uri) {
          final oldUri = old.uri;
          old.uri = t.uri;
          lastRelinked++;
          unawaited(Native.offlineRekey(oldUri, t.uri).catchError((Object _) {}));
        }
        continue;
      }
      if (have.add(t.key)) fresh.add(t);
    }
    if (lastRelinked > 0) {
      _invalidate();
      _saveLib();
      notifyListeners();
    }
    if (fresh.isEmpty) return 0;
    final wasEmpty = queue.isEmpty;
    library.addAll(fresh);
    queue.addAll(fresh);
    if (_baseAll) _base.addAll(fresh);
    _invalidate();
    if (wasEmpty) index = 0;
    _saveLib();
    notifyListeners();
    _loadMeta();
    if (wasEmpty && prefs.autoplay) playIndex(0);
    if (prefs.offlineMode == 'all' && fresh.any((Track t) => t.cloud)) unawaited(offlineSync(force: true));
    return fresh.length;
  }

  // ---------------------------------------------------------------- offline copies of cloud songs
  bool offRunning = false;
  int offQueued = 0, offDone = 0, offBytes = 0;
  String offWait = '';
  bool offPaused = false;
  bool prepping = false; // a Drive song is being copied to the phone before it plays

  int get cloudCount => library.where((Track t) => t.cloud && !t.isAiff).length;

  /// Asks the phone to save every cloud song that has no copy yet. Songs already saved are skipped, so nothing downloads twice.
  Future<bool> offlineSync({bool force = false}) async {
    final items = <Map<String, String>>[
      for (final t in library)
        if (t.cloud && !t.isAiff) {'uri': t.uri, 'name': t.name},
    ];
    if (items.isEmpty) return false;
    try {
      return await Native.offlineStart(items, prefs.offlineWifi, force: force);
    } catch (_) {
      return false;
    }
  }

  /// The size limit in bytes for 'played' mode (0 = none). 'all' mode never removes anything.
  int get offlineLimitBytes => prefs.offlineMode == 'played' ? prefs.offlineLimitGb * 1073741824 : (prefs.offlineMode == 'off' ? 512 * 1048576 : 0);

  Future<void> offlineTrim() async {
    try {
      await Native.offlineTrim(offlineLimitBytes);
    } catch (_) {}
  }

  /// Picks how Drive songs are saved: when a song is played, all of them, or never.
  Future<void> setOfflineMode(String m) async {
    prefs.offlineMode = m;
    savePrefs();
    notifyListeners();
    try {
      await Native.offlineClearQueue();
    } catch (_) {}
    if (m == 'all') {
      await offlineSync(force: true);
    } else if (m == 'played') {
      await offlineResume(force: true);
      await offlineTrim();
    } else {
      await offlineTrim();
    }
  }

  Timer? _saveTimer;

  bool _hiResCandidate(Track t) => const {'wav', 'wave', 'aif', 'aiff', 'flac'}.contains(t.ext) && (t.bits >= 24 || t.rate > 48000);

  /// Starts again for the song that plays now, for example after the setting was changed.
  void hiResRefresh() {
    final t = current;
    if (t == null) return;
    _hiResCheck(t);
    notifyListeners();
  }

  /// "Hi-Res check": when a lossless song with a high sample rate or 24 bits starts, Athana first reads its header (the file's own
  /// numbers show at once), then, a few seconds later so it never competes with the start of the music, reads the whole song once and
  /// measures it: how far the music really reaches and how many bits it really uses. Numbers from an earlier check or from
  /// "Analyse song" are used as they are, so each song is checked once.
  void _hiResCheck(Track t) {
    _hrTimer?.cancel();
    if (_hrBusy) Native.analyzeCancel().catchError((Object _) {}); // the check of an earlier song
    hrState = '';
    hrResult = null;
    hrWhy = '';
    if (!prefs.hiresCheck || !_hiResCandidate(t)) return;
    final saved = _savedAnalysis(t);
    if (saved != null) {
      hrResult = saved;
      hrState = 'done';
      return;
    }
    hrState = 'wait';
    if (!t.cloud) {
      _hrTimer = Timer(const Duration(seconds: 5), () => unawaited(_hrRun(t)));
      return;
    }
    // A Drive song that is still streaming is checked only after it has loaded well ahead (and a little later again), so the check
    // never slows down the music itself. A copy on the phone (saved or prepared) is read at once.
    final tok = _tok;
    _hrTimer = Timer(const Duration(seconds: 5), () async {
      if (!await _whenSettled(t, tok)) return;
      if (!_streamLocal) {
        await Future<void>.delayed(const Duration(seconds: 20));
        if (!await _whenSettled(t, tok)) return;
      }
      unawaited(_hrRun(t));
    });
  }

  bool _streamLocal = false;

  /// Waits until the Drive song that plays now has loaded far enough ahead (about 30 seconds, or all of it, or a copy on the phone is
  /// used). Background jobs that read the same Drive file (checks, copies, tags) wait for this, because on a slow connection they would
  /// take speed away from the music. Returns false when the song changed in the meantime.
  Future<bool> _whenSettled(Track t, int tok) async {
    for (var i = 0; i < 240; i++) {
      if (tok != _tok || !identical(current, t)) return false;
      try {
        final b = await Native.bufInfo();
        _streamLocal = b['local'] == true;
        if (b['settled'] == true) return true;
      } catch (_) {
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  /// The numbers of an earlier analysis of this song (without the picture), or null.
  Map<String, dynamic>? _savedAnalysis(Track t) {
    try {
      final s = _sp?.getString('athana_an:${t.key}');
      if (s == null) return null;
      final m = jsonDecode(s);
      return (m is Map && m['cutoff'] != null) ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _hrRun(Track t) async {
    if (!identical(current, t) || _hrBusy) return;
    final id = ++_hrRunId;
    _hrBusy = true;
    hrState = 'analysing';
    anProgress.value = 0;
    notifyListeners();
    Map<String, dynamic>? r;
    var why = '';
    try {
      r = await Native.analyze(t);
    } on PlatformException catch (e) {
      why = (e.message ?? '').trim();
      r = null;
    } catch (_) {
      r = null;
    }
    if (id == _hrRunId) _hrBusy = false;
    if (!identical(current, t) || !prefs.hiresCheck) return;
    if (r == null) {
      // Cancelled by an "Analyse song" the person started meanwhile? Then its numbers are saved and can be used.
      hrResult = _savedAnalysis(t);
      if (hrResult != null) {
        hrState = 'done';
      } else if (why.isEmpty && _hrRetry.add(t.key)) {
        // Cancelled by something else: try once more in a moment.
        hrState = 'wait';
        _hrTimer = Timer(const Duration(seconds: 3), () => unawaited(_hrRun(t)));
      } else {
        hrState = 'failed';
        hrWhy = why;
        debugPrint('[hires] check failed: $why');
      }
    } else {
      analysisSave(t, r);
      hrResult = Map<String, dynamic>.of(r)..remove('spec');
      hrState = 'done';
    }
    notifyListeners();
  }

  Timer? _warmTimer;
  int _warmGen = 0;

  /// Starts again for the song that plays now, for example after the setting was changed.
  void warmRefresh() {
    final t = current;
    if (t != null) _warmNext(t);
  }

  /// "Get the next song ready": a few seconds after a song starts (so it never competes with the song's own loading), the next one
  /// or two Drive songs in the queue are copied to a temporary folder. Pressing Next then starts at once. These copies are not saved:
  /// they are removed as soon as the queue moves on. Does nothing in Offline mode, when every Drive song is saved anyway, or when
  /// the setting is off (an empty list also clears what is there).
  void _warmNext(Track t) {
    _warmTimer?.cancel();
    final items = <Map<String, String>>[];
    if (prefs.warmNext && !prefs.offline && prefs.offlineMode != 'all' && repeat != 2) {
      for (var k = 1; k <= 3 && items.length < 2; k++) {
        var n = index + k;
        if (n >= queue.length) {
          if (repeat == 1 && !shuffle && queue.isNotEmpty) {
            n = n % queue.length;
          } else {
            break;
          }
        }
        final c = queue[n];
        if (c.cloud && !c.isAiff && !identical(c, t)) items.add(<String, String>{'uri': c.uri, 'name': c.name});
      }
    }
    if (items.isEmpty) {
      _warmGen++;
      Native.warm(t.uri, const <Map<String, String>>[], prefs.offlineWifi).catchError((Object _) {});
      return;
    }
    final gen = ++_warmGen;
    final tok = _tok;
    _warmTimer = Timer(const Duration(seconds: 8), () async {
      if (!identical(current, t)) return;
      if (t.cloud && !await _whenSettled(t, tok)) return;
      if (gen != _warmGen || !identical(current, t)) return;
      Native.warm(t.uri, items, prefs.offlineWifi).catchError((Object _) {});
    });
  }

  /// In 'played' mode a Drive song is saved after it has played for a few seconds (so skipped songs take no space).
  void _saveWhenPlayed(Track t) {
    _saveTimer?.cancel();
    if (prefs.offlineMode != 'played' || !t.cloud || t.isAiff) return;
    final tok = _tok;
    _saveTimer = Timer(const Duration(seconds: 15), () async {
      if (!identical(current, t) || !playing) return;
      if (!await _whenSettled(t, tok)) return;
      if (!identical(current, t)) return;
      Native.offlineStart(<Map<String, String>>[{'uri': t.uri, 'name': t.name}], prefs.offlineWifi, limit: offlineLimitBytes).catchError((Object _) => false);
    });
  }

  /// Carries on with songs that are waiting, for example after Wi-Fi came back. Does nothing after the person pressed Pause.
  Future<void> offlineResume({bool force = false}) async {
    if (prefs.offlineMode == 'off') return;
    try {
      await Native.offlineStart(const <Map<String, String>>[], prefs.offlineWifi, force: force, limit: offlineLimitBytes);
    } catch (_) {}
  }

  Future<void> offlineStop() async {
    try {
      await Native.offlineStop();
    } catch (_) {}
  }

  Future<void> offlineClear() async {
    try {
      await Native.offlineClear();
    } catch (_) {}
  }

  Future<void> offlineRefresh() async {
    try {
      _offApply(await Native.offlineStatus());
    } catch (_) {}
  }

  void _offApply(Map<String, dynamic> e) {
    offRunning = e['running'] == true;
    offQueued = ((e['queued'] ?? 0) as num).toInt();
    offDone = ((e['done'] ?? 0) as num).toInt();
    offBytes = ((e['bytes'] ?? 0) as num).toInt();
    offWait = (e['wait'] ?? '') as String;
    offPaused = e['paused'] == true;
    notifyListeners();
  }

  /// Links a folder. With [drive] the picker opens on Google Drive.
  Future<String> addFolder({bool drive = false}) async {
    busy = true;
    notifyListeners();
    try {
      final r = await Native.pickFolder(drive: drive);
      if (r == null) return '';
      final tree = r['tree'] as String;
      if (!folders.any((f) => f.uri == tree)) folders.add(LinkedFolder(tree, (r['name'] ?? 'Folder') as String));
      final n = await addSongs(List<Map<String, dynamic>>.from(r['songs'] as List), tree: tree);
      _saveLib();
      final keptNote = r['kept'] == false ? ' Android will not remember this folder, so link it again after closing Athana.' : '';
      final cloudNote = drive || tree.contains('docs.storage') ? ' Cloud songs are fetched when you play them.' : '';
      lostTrees.remove(tree);
      return (n == 0 ? 'No new songs found in that folder.' : 'Added $n songs.') + cloudNote + keptNote;
    } on PlatformException catch (e) {
      return e.code == 'nodrive' ? (e.message ?? 'Google Drive is not installed.') : 'Could not open the folder: ${e.message}';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// How many Drive songs are in the library, and how many of them Android no longer lets Athana open
  /// (those need Sync Drive folder; a song saved on the phone still plays).
  Future<(int, int)> driveCounts() async {
    final cloud = library.where((Track t) => t.cloud).toList();
    try {
      final ok = await Native.treeAccess();
      return (cloud.length, cloud.where((Track t) => !ok.contains(t.uri)).length);
    } catch (_) {
      return (cloud.length, 0);
    }
  }

  /// Adds chosen songs. With [drive] the picker opens on Google Drive, and the songs are fetched only when played.
  Future<String> addFiles({bool drive = false, bool sync = false}) async {
    try {
      final r = await Native.pickFiles(drive: drive);
      if (r == null) return '';
      final n = await addSongs(r);
      final re = lastRelinked;
      // Older Android versions keep access to only 128 picked files. Nothing is copied for the rest (Athana streams them),
      // so say it plainly: those songs have to be picked again after Athana is closed.
      final unkept = r.where((m) => m['kept'] == false && '${m['uri']}'.contains('docs.storage')).length;
      final keepNote = unkept == 0
          ? ''
          : ' This Android keeps access to only some picked files, so $unkept of these songs must be picked again with Add from Google Drive after Athana is closed. Android 11 or newer keeps many more.';
      if (sync) {
        final same = r.length - n - re;
        return 'Drive synced. $n new, $re reconnected, ${same < 0 ? 0 : same} already up to date.$keepNote';
      }
      if (n == 0) {
        if (re > 0) return 'Reconnected $re songs to Google Drive. They are not added twice.$keepNote';
        return (drive ? 'Those songs are already in your library. Their access to Google Drive was refreshed.' : 'Those songs are already in your library.') + keepNote;
      }
      if (!drive) return 'Added $n songs.$keepNote';
      final more = (re > 0 ? ' $re songs that had lost their link were reconnected.' : '') + keepNote;
      return switch (prefs.offlineMode) {
        'all' => 'Added $n songs from Google Drive. Saving them on your phone in the background.$more',
        'played' => 'Added $n songs from Google Drive. Each one is saved on your phone the first time you play it.$more',
        _ => 'Added $n songs from Google Drive.$more',
      };
    } on PlatformException catch (e) {
      return e.code == 'nodrive' ? (e.message ?? 'Google Drive is not installed.') : 'Could not open the picker: ${e.message}';
    }
  }

  bool get driveHintSeen => _sp?.getBool('athana_drive_hint') ?? false;
  set driveHintSeen(bool v) => _sp?.setBool('athana_drive_hint', v);

  /// Looks for new songs in every linked folder, without touching what is playing.
  Future<String> refreshLibrary() async {
    if (folders.isEmpty) return 'Link a music folder first.';
    busy = true;
    notifyListeners();
    var added = 0, lost = 0;
    try {
      for (final f in folders) {
        final r = await Native.scanTree(f.uri);
        if (r == null) {
          lost++;
          continue;
        }
        added += await addSongs(r, tree: f.uri);
      }
    } on PlatformException catch (e) {
      return 'Refresh failed: ${e.message}';
    } finally {
      busy = false;
      notifyListeners();
    }
    if (lost > 0 && added == 0) return 'Android no longer lets Athana read $lost folder${lost > 1 ? 's' : ''}. Link ${lost > 1 ? 'them' : 'it'} again.';
    return added == 0 ? 'Your library is up to date.' : 'Added $added new songs.';
  }

  Future<void> removeFolder(LinkedFolder f) async {
    final cur = current;
    final gone = library.where((t) => t.tree == f.uri).toSet();
    library.removeWhere(gone.contains);
    queue.removeWhere(gone.contains);
    _base.removeWhere(gone.contains);
    folders.removeWhere((x) => x.uri == f.uri);
    if (cur != null && gone.contains(cur)) {
      await Native.stop();
      playing = false;
      _loaded = false;
      index = queue.isEmpty ? -1 : 0;
    } else {
      index = cur == null ? -1 : queue.indexOf(cur);
    }
    _invalidate();
    try {
      await Native.releaseTree(f.uri);
    } catch (_) {}
    _saveLib();
    notifyListeners();
  }

  Future<void> eraseEverything() async {
    await Native.stop();
    for (final f in folders) {
      try {
        await Native.releaseTree(f.uri);
      } catch (_) {}
    }
    library = <Track>[];
    queue = <Track>[];
    _base = <Track>[];
    folders = <LinkedFolder>[];
    playlists = <Playlist>[];
    lyr.clearSaved();
    index = -1;
    playing = false;
    _loaded = false;
    _invalidate();
    prefs.load(Prefs().toJson());
    shuffle = false;
    repeat = 0;
    await _sp?.clear();
    notifyListeners();
  }

  /// Reads titles, artists, covers and lengths in the background while the list is already usable.
  bool get metaRunning => _metaRunning;
  int get metaPending => library.where((t) => !t.metaDone).length;

  // ---------------------------------------------------------------- song analysis
  final ValueNotifier<double> anProgress = ValueNotifier<double>(0);

  /// The numbers measured earlier for a song (not the picture), or null.
  Map<String, dynamic>? analysisCached(Track t) {
    final v = _sp?.getString('athana_an:${t.key}');
    if (v == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(v) as Map);
    } catch (_) {
      return null;
    }
  }

  void analysisSave(Track t, Map<String, dynamic> r) {
    final c = Map<String, dynamic>.of(r)..remove('spec');
    try {
      _sp?.setString('athana_an:${t.key}', jsonEncode(c));
    } catch (_) {}
  }

  /// Reads the details of songs that have none yet.
  void refreshMeta() => unawaited(_loadMeta());

  Future<void> _loadMeta() async {
    if (_metaRunning) return;
    _metaRunning = true;
    try {
      var since = 0;
      while (true) {
        // Songs in a cloud app are only read when played, so linking a big Drive folder does not download all of it.
        final todo = library.where((t) => !t.metaDone && (prefs.cloudMeta || !t.cloud)).toList();
        if (todo.isEmpty) break;
        for (final t in todo) {
          try {
            t.applyMeta(await Native.meta(t), clean: prefs.cleanNum);
          } catch (_) {
            t.metaDone = true;
          }
          since++;
          if (since % 10 == 0) {
            _invalidate();
            notifyListeners();
          }
          if (since % 80 == 0) _saveLib();
        }
      }
      _invalidate();
      _saveLib();
      notifyListeners();
    } finally {
      _metaRunning = false;
    }
  }

  // ---------------------------------------------------------------- playback
  /// Plays `list[start]` and makes `list` the queue.
  Future<void> playFrom(List<Track> list, int start, {bool all = false}) async {
    if (list.isEmpty || start < 0 || start >= list.length) return;
    _base = List<Track>.of(list);
    _baseAll = all;
    final first = list[start];
    if (shuffle) {
      final rest = list.where((t) => !identical(t, first)).toList()..shuffle();
      queue = <Track>[first, ...rest];
      await playIndex(0);
    } else {
      queue = List<Track>.of(list);
      await playIndex(start);
    }
  }

  Future<void> shuffleAll() async {
    if (library.isEmpty) return;
    shuffle = true;
    prefs.shuffleSaved = true;
    savePrefs();
    final list = List<Track>.of(library)..shuffle();
    await playFrom(list, 0, all: true);
  }

  Future<void> playIndex(int i) async {
    if (queue.isEmpty || i < 0 || i >= queue.length) return;
    _cancelSleepFade();
    index = i;
    final t = queue[i];
    if (loopA >= 0 || loopB >= 0) {
      loopA = -1;
      loopB = -1;
      Native.loopSet(-1, -1).catchError((_) {});
    }
    _tok++;
    _loaded = true;
    prepping = false;
    durationMs = t.durationMs;
    positionMs.value = 0;
    playing = true;
    error = null;
    format = '';
    infoRate = 0;
    infoOut = 0;
    infoMime = '';
    infoOwn = false;
    infoOwnOut = 0;
    infoBp = false;
    normStatus = '';
    _hiResCheck(t);
    notifyListeners();
    unawaited(lyr.load(t));
    if (t.cloud && (!t.metaDone || (t.album.isEmpty && t.art == null))) unawaited(_cloudMeta(t, _tok));
    _saveWhenPlayed(t);
    _warmNext(t);
    try {
      await Native.play(_tok, t);
    } on PlatformException catch (e) {
      error = e.message ?? 'Could not play this file.';
      playing = false;
      notifyListeners();
    }
  }

  /// Reads the tags and cover of a cloud song a few seconds after it started, when its file is already coming in.
  /// If Drive gave nothing yet, it tries again later, when the song has been saved on the phone and can be read from there.
  Future<void> _cloudMeta(Track t, int tok) async {
    for (final wait in const <int>[6, 20, 45]) {
      await Future<void>.delayed(Duration(seconds: wait));
      if (tok != _tok || current?.uri != t.uri) return;
      if (!await _whenSettled(t, tok)) return;
      try {
        final m = await Native.meta(t);
        final got = ((m['title'] ?? '') as String).trim().isNotEmpty ||
            ((m['album'] ?? '') as String).trim().isNotEmpty ||
            ((m['art'] ?? '') as String).isNotEmpty;
        if (!got && wait != 45) continue;
        t.applyMeta(m, clean: prefs.cleanNum);
        _invalidate();
        _saveLib();
        notifyListeners();
        if (tok == _tok && current?.uri == t.uri) await Native.updateInfo(t);
        if (got) return;
      } catch (_) {}
    }
  }

  Future<void> togglePlay() async {
    if (current == null) return;
    if (!_loaded) return playIndex(index);
    return playing ? pause() : resume();
  }

  Future<void> pause() async {
    _cancelSleepFade();
    playing = false;
    notifyListeners();
    await Native.pause();
  }

  Future<void> resume() async {
    _cancelSleepFade();
    if (!_loaded) return playIndex(index);
    playing = true;
    notifyListeners();
    await Native.resume();
  }

  Future<void> seekTo(int ms) async {
    final m = ms < 0 ? 0 : (durationMs > 0 && ms > durationMs ? durationMs : ms);
    positionMs.value = m;
    await Native.seek(m);
  }

  Future<void> skip(int seconds) => seekTo(positionMs.value + seconds * 1000);

  /// Next song. When a song ends by itself (`auto`) the queue stops at its end unless repeat is on.
  Future<void> next({bool auto = false}) async {
    if (queue.isEmpty) return;
    var n = index + 1;
    if (n >= queue.length) {
      if (!auto || repeat == 1) {
        if (shuffle) _reshuffle();
        n = 0;
      } else {
        playing = false;
        _loaded = false;
        positionMs.value = 0;
        notifyListeners();
        return;
      }
    }
    await playIndex(n);
  }

  Future<void> prev() async {
    if (queue.isEmpty) return;
    if (prefs.prevRestart > 0 && positionMs.value > prefs.prevRestart * 1000) {
      await seekTo(0);
      return;
    }
    var p = index - 1;
    if (p < 0) p = queue.length - 1;
    await playIndex(p);
  }

  void _reshuffle() {
    final cur = current;
    final rest = queue.where((t) => !identical(t, cur)).toList()..shuffle();
    queue = <Track>[if (cur != null) cur, ...rest];
    index = cur == null ? -1 : 0;
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    final cur = current;
    if (shuffle) {
      _reshuffle();
    } else {
      queue = List<Track>.of(_base);
      index = cur == null ? -1 : queue.indexOf(cur);
      if (index < 0 && queue.isNotEmpty) index = 0;
    }
    prefs.shuffleSaved = shuffle;
    savePrefs();
  }

  void cycleRepeat() {
    repeat = (repeat + 1) % 3;
    prefs.repeatSaved = repeat;
    savePrefs();
  }

  Future<void> setSpeed(double r) async {
    speed = r;
    notifyListeners();
    await Native.setSpeed(r);
  }

  // ---------------------------------------------------------------- queue editing
  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final cur = current;
    final t = queue.removeAt(oldIndex);
    queue.insert(newIndex, t);
    index = cur == null ? -1 : queue.indexOf(cur);
    notifyListeners();
  }

  void removeFromQueue(int i) {
    if (i < 0 || i >= queue.length) return;
    final cur = current;
    final removingCurrent = i == index;
    queue.removeAt(i);
    if (removingCurrent) {
      if (queue.isEmpty) {
        index = -1;
        playing = false;
        _loaded = false;
        Native.stop();
      } else {
        index = i >= queue.length ? 0 : i;
        playIndex(index);
        return;
      }
    } else {
      index = cur == null ? -1 : queue.indexOf(cur);
    }
    notifyListeners();
  }

  /// Adds a song to the end of the queue (and starts it when nothing is queued). Returns a short message.
  Future<String> addToQueue(Track t) async {
    if (queue.isEmpty) {
      await playFrom(<Track>[t], 0);
      return 'Playing "${t.title}"';
    }
    if (queue.any((Track q) => identical(q, t))) return 'Already in the queue';
    queue.add(t);
    _base.add(t);
    notifyListeners();
    return 'Added to queue';
  }

  // ---------------------------------------------------------------- loudness normalisation
  void normApply() {
    Native.normSet(prefs.rgOn, prefs.rgTarget.toDouble()).catchError((Object _) {});
  }

  void setNormOn(bool on) {
    prefs.rgOn = on;
    if (!on) normStatus = '';
    savePrefs();
    normApply();
  }

  void setNormTarget(int lufs) {
    prefs.rgTarget = lufs;
    savePrefs();
    normApply();
  }

  // ---------------------------------------------------------------- equalizer
  /// The preamp that is really used: with clipping protection on, it is lowered by 60% of the biggest boost
  /// (the soft limiter catches the rest), so presets keep their punch.
  double get eqEffectivePre {
    var top = 0.0;
    for (final g in prefs.eqGains) {
      if (g > top) top = g;
    }
    final v = prefs.eqPre - (prefs.eqAuto ? top * 0.6 : 0.0);
    return v.clamp(-24.0, 12.0).toDouble();
  }

  /// Sends the equalizer settings to the player.
  void eqApply() {
    Native.eqSet(prefs.eqOn, eqEffectivePre, prefs.eqGains).catchError((Object _) {});
  }

  /// A preset, or one of "my presets". Choosing one switches the equalizer on.
  void eqChoose(String name) {
    final g = prefs.myEq[name] ?? eqPresetGains(name);
    if (g == null) return;
    prefs.eqGains = List<double>.of(g);
    prefs.eqBase = List<double>.of(g);
    prefs.eqStrength = 100;
    prefs.eqPreset = name;
    prefs.eqOn = true;
    savePrefs();
    eqApply();
  }

  void eqSetOn(bool on) {
    prefs.eqOn = on;
    savePrefs();
    eqApply();
  }

  /// Moves one bar. The preset name becomes "Custom" unless the curve still matches a preset.
  void eqSetBand(int i, double db, {bool save = true}) {
    final g = List<double>.of(prefs.eqGains);
    g[i] = db.clamp(-12.0, 12.0).toDouble();
    prefs.eqGains = g;
    prefs.eqBase = List<double>.of(g); // a hand-made curve becomes the new starting point
    prefs.eqStrength = 100;
    prefs.eqOn = true;
    prefs.eqPreset = _nameFor(g);
    if (save) {
      savePrefs();
    } else {
      notifyListeners();
    }
    eqApply();
  }

  /// True when there is a curve that the Strength slider can scale.
  bool get eqCanScale {
    for (final v in prefs.eqBase) {
      if (v != 0) return true;
    }
    return false;
  }

  /// True when the strength asks for more than the +-12 dB the bars can reach.
  bool get eqLimited {
    for (final v in prefs.eqBase) {
      if ((v * prefs.eqStrength / 100).abs() > 12.0) return true;
    }
    return false;
  }

  /// Scales the chosen preset from 50% to 200%. The final curve is always base x strength, kept inside +-12 dB.
  void eqSetStrength(double percent, {bool save = true}) {
    final st = ((percent / 5).round() * 5).clamp(50, 200).toDouble();
    prefs.eqStrength = st;
    prefs.eqGains = [for (final v in prefs.eqBase) (v * st / 100).clamp(-12.0, 12.0).toDouble()];
    prefs.eqOn = true;
    if (save) {
      savePrefs();
    } else {
      notifyListeners();
    }
    eqApply();
  }

  void eqSetPre(double db, {bool save = true}) {
    prefs.eqPre = db.clamp(-12.0, 12.0).toDouble();
    prefs.eqOn = true;
    if (save) {
      savePrefs();
    } else {
      notifyListeners();
    }
    eqApply();
  }

  void eqSetAuto(bool v) {
    prefs.eqAuto = v;
    savePrefs();
    eqApply();
  }

  // ---------------------------------------------------------------- one sound per output
  String outKey = ''; // 'speaker', 'wired', 'usb:<name>' or 'bluetooth:<name>'
  final Map<String, Map<String, dynamic>> _outProfiles = <String, Map<String, dynamic>>{};
  bool _outApplying = false;

  /// A short name for the current output, for the screen.
  String get outLabel {
    if (outKey.isEmpty) return '';
    final i = outKey.indexOf(':');
    final kind = i < 0 ? outKey : outKey.substring(0, i);
    final name = i < 0 ? '' : outKey.substring(i + 1);
    final base = switch (kind) {
      'wired' => 'Wired headphones',
      'usb' => 'USB audio',
      'bluetooth' => 'Bluetooth',
      _ => 'Phone speaker',
    };
    return name.isEmpty ? base : '$base · $name';
  }

  void _loadOutProfiles() {
    try {
      final raw = _sp?.getString('athana_outprof');
      if (raw == null) return;
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      for (final e in m.entries) {
        _outProfiles[e.key] = Map<String, dynamic>.from(e.value as Map);
      }
    } catch (_) {}
  }

  Map<String, dynamic> _snapshotOut() => {
        'eqOn': prefs.eqOn,
        'eqGains': prefs.eqGains,
        'eqPre': prefs.eqPre,
        'eqPreset': prefs.eqPreset,
        'eqBase': prefs.eqBase,
        'eqStrength': prefs.eqStrength,
        'mixWide': prefs.mixWide,
        'mixCross': prefs.mixCross,
        'mixVol': prefs.mixVol,
      };

  void _storeOut() {
    if (!prefs.autoOut || outKey.isEmpty || _outApplying) return;
    _outProfiles[outKey] = _snapshotOut();
    try {
      _sp?.setString('athana_outprof', jsonEncode(_outProfiles));
    } catch (_) {}
  }

  /// The sound goes to a new output. With "Remember per output" on, that output's own settings come back.
  void onOutput(String kind, String name) {
    final key = (kind == 'bluetooth' || kind == 'usb') && name.isNotEmpty ? '$kind:$name' : kind;
    if (key == outKey) return;
    outKey = key;
    if (prefs.autoOut) {
      final p = _outProfiles[key];
      if (p == null) {
        _storeOut(); // first time on this output: start from what you have now
      } else {
        _outApplying = true;
        final j = prefs.toJson();
        j.addAll(p);
        prefs.load(j);
        _outApplying = false;
        savePrefs();
        eqApply();
        mixApply();
        return;
      }
    }
    notifyListeners();
  }

  void setAutoOut(bool on) {
    prefs.autoOut = on;
    if (on) _storeOut();
    savePrefs();
  }

  // ---------------------------------------------------------------- mixer
  bool _mixLatched = false; // once a knob has moved, the audio chain stays open until Reset, so dragging back to centre never stutters
  bool get mixIsDefault => prefs.mixBal == 0 && prefs.mixWide == 0 && !prefs.mixMono && prefs.mixVol == 100 && prefs.mixCross == 0;

  void mixApply() {
    final active = _mixLatched || !mixIsDefault;
    Native.mixSet(active, prefs.mixBal, prefs.mixWide / 100.0, prefs.mixMono, prefs.mixVol / 100.0, prefs.mixCross / 100.0).catchError((Object _) {});
  }

  void mixChange({double? bal, int? wide, bool? mono, int? vol, int? cross}) {
    if (bal != null) prefs.mixBal = (bal.abs() < 0.02 ? 0.0 : bal).clamp(-1.0, 1.0).toDouble();
    if (wide != null) prefs.mixWide = wide.clamp(0, 100).toInt();
    if (mono != null) prefs.mixMono = mono;
    if (cross != null) prefs.mixCross = cross.clamp(0, 100).toInt();
    if (vol != null) prefs.mixVol = (vol >= 98 && vol <= 102 ? 100 : vol).clamp(0, 150).toInt();
    _mixLatched = true;
    savePrefs();
    mixApply();
  }

  void mixReset() {
    prefs.mixBal = 0;
    prefs.mixWide = 0;
    prefs.mixMono = false;
    prefs.mixVol = 100;
    prefs.mixCross = 0;
    _mixLatched = false;
    savePrefs();
    mixApply();
    setSpeed(1.0);
  }

  void eqReset() {
    prefs.eqGains = List<double>.filled(10, 0.0);
    prefs.eqBase = List<double>.filled(10, 0.0);
    prefs.eqStrength = 100;
    prefs.eqPre = 0;
    prefs.eqPreset = 'Flat';
    savePrefs();
    eqApply();
  }

  String _nameFor(List<double> g) {
    for (final e in prefs.myEq.entries) {
      if (sameGains(e.value, g)) return e.key;
    }
    for (final grp in kEqGroups.values) {
      for (final p in grp) {
        if (sameGains(p.gains, g)) return p.name;
      }
    }
    return 'Custom';
  }

  /// Keeps the current curve under a name of your own.
  void eqSaveMine(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    prefs.myEq = Map<String, List<double>>.of(prefs.myEq)..[n] = List<double>.of(prefs.eqGains);
    prefs.eqBase = List<double>.of(prefs.eqGains);
    prefs.eqStrength = 100;
    prefs.eqPreset = n;
    savePrefs();
  }

  void eqDeleteMine(String name) {
    prefs.myEq = Map<String, List<double>>.of(prefs.myEq)..remove(name);
    if (prefs.eqPreset == name) prefs.eqPreset = _nameFor(prefs.eqGains);
    savePrefs();
  }

  // ---------------------------------------------------------------- playlists
  void _savePl() {
    try {
      _sp?.setString('athana_pl', jsonEncode(playlists.map((p) => p.toJson()).toList()));
    } catch (_) {}
    notifyListeners();
  }

  Playlist createPlaylist(String name) {
    final p = Playlist(DateTime.now().microsecondsSinceEpoch.toString(), name.trim().isEmpty ? 'New playlist' : name.trim());
    playlists.add(p);
    _savePl();
    return p;
  }

  String addToPlaylist(Playlist p, Track t) {
    if (p.items.contains(t.key)) return 'Already in "${p.name}"';
    p.items.add(t.key);
    _savePl();
    return 'Added to "${p.name}"';
  }

  void removeFromPlaylist(Playlist p, Track t) {
    p.items.remove(t.key);
    _savePl();
  }

  void deletePlaylist(Playlist p) {
    playlists.remove(p);
    _savePl();
  }

  void renamePlaylist(Playlist p, String name) {
    if (name.trim().isEmpty) return;
    p.name = name.trim();
    _savePl();
  }

  /// The songs of a playlist that are in the library right now.
  List<Track> tracksOf(Playlist p) {
    final m = <String, Track>{for (final t in library) t.key: t};
    return [for (final k in p.items) if (m[k] != null) m[k]!];
  }

  // ---------------------------------------------------------------- sleep timer
  bool _sleepFading = false;
  void _cancelSleepFade() {
    if (!_sleepFading) return;
    _sleepFading = false;
    Native.sleepFadeCancel().catchError((Object _) {});
  }

  void setSleep(int minutes) {
    _sleep?.cancel();
    stopAfter = false;
    sleepMinutes = minutes;
    if (minutes > 0) {
      _sleep = Timer(Duration(minutes: minutes), () {
        sleepMinutes = 0;
        if (prefs.sleepFinish && playing) {
          stopAfter = true;
        } else if (prefs.sleepFade > 0 && playing) {
          _sleepFading = true;
          Native.sleepFade(prefs.sleepFade).catchError((Object _) {});
          Timer(Duration(seconds: prefs.sleepFade + 1), () {
            if (!_sleepFading) return;
            _sleepFading = false;
            playing = false;
            notifyListeners();
          });
        } else {
          pause();
        }
        notifyListeners();
      });
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- events from Android
  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'state':
        if (e['tok'] != _tok) return;
        positionMs.value = ((e['pos'] ?? 0) as num).toInt();
        final d = ((e['dur'] ?? -1) as num).toInt();
        var changed = false;
        if (d > 0 && d != durationMs) {
          durationMs = d;
          final c = current;
          if (c != null && c.durationMs == 0) c.durationMs = d;
          changed = true;
        }
        _countPlay();
        final pl = e['playWhenReady'] == true;
        if (pl != playing) {
          playing = pl;
          changed = true;
        }
        if (e['ended'] == true) {
          _onEnded();
        } else if (changed) {
          notifyListeners();
        }
        break;
      case 'info':
        if (e['tok'] != _tok) return;
        final c = current;
        final rate = ((e['rate'] ?? 0) as num).toInt();
        final out = ((e['outRate'] ?? 0) as num).toInt();
        final parts = <String>[
          if (c != null && c.ext.isNotEmpty) c.ext.toUpperCase(),
          if (rate > 0) '${(rate / 1000).toStringAsFixed(rate % 1000 == 0 ? 0 : 1)} kHz',
          if (out > 0 && rate > 0 && out != rate) 'output ${(out / 1000).toStringAsFixed(out % 1000 == 0 ? 0 : 1)} kHz',
        ];
        infoRate = rate;
        infoOut = out;
        infoMime = (e['mime'] ?? '') as String;
        infoOwn = e['own'] == true;
        infoBp = e['bp'] == true;
        infoOwnOut = int.tryParse(((e['ownOut'] ?? '') as String).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        format = parts.join(' · ');
        notifyListeners();
        break;
      case 'off':
        _offApply(e);
        break;
      case 'an':
        anProgress.value = ((e['p'] ?? 0) as num).toDouble();
        break;
      case 'norm':
        if (e['tok'] != _tok) return;
        normStatus = (e['state'] ?? '') as String;
        if (normStatus == 'off') normStatus = '';
        normGain = ((e['gain'] ?? 0) as num).toDouble();
        notifyListeners();
        break;
      case 'prep':
        if (e['tok'] != _tok) return;
        prepping = e['on'] == true;
        notifyListeners();
        break;
      case 'error':
        if (e['tok'] != _tok) return;
        prepping = false;
        final why = (e['why'] ?? '').toString();
        if (e['cloud'] == true && why == 'perm') {
          error = 'Android no longer lets this app open the song (the permission is lost after a reinstall or when the app data is cleared). Pick it again with Add from Google Drive (same folder, Select all). It is reconnected, not added twice, and keeps your plays and playlists.';
        } else if (e['cloud'] == true && why == 'missing') {
          error = 'This song was moved or deleted in Google Drive. Add it again with Add from Google Drive.';
        } else if (e['cloud'] == true && why == 'space') {
          error = 'There is not enough free space on the phone to prepare this song.';
        } else if (e['cloud'] == true) {
          error = 'Google Drive could not provide this song. Check your internet connection and that the Google Drive app is signed in, then play it again. (${e['name'] ?? 'error'}${why.isEmpty ? '' : ', $why'})';
        } else {
          error = 'This file could not be played (${e['name'] ?? 'error'}).';
        }
        playing = false;
        notifyListeners();
        break;
      case 'cmd':
        _onCommand((e['name'] ?? '') as String);
        break;
      case 'out':
        onOutput((e['kind'] ?? 'speaker') as String, (e['name'] ?? '') as String);
        break;
    }
  }

  /// A song counts as played once it has run for 30 seconds (or half of a short song), like the web version.
  void _countPlay() {
    final c = current;
    if (c == null || _countedTok == _tok || durationMs <= 0) return;
    final need = (durationMs ~/ 2) < 30000 ? durationMs ~/ 2 : 30000;
    if (positionMs.value < need) return;
    _countedTok = _tok;
    c.plays++;
    c.lastPlayed = DateTime.now().millisecondsSinceEpoch;
    _saveLib();
  }

  void _onEnded() {
    if (stopAfter) {
      stopAfter = false;
      playing = false;
      _loaded = false;
      positionMs.value = 0;
      notifyListeners();
      return;
    }
    if (repeat == 2) {
      playIndex(index);
      return;
    }
    next(auto: true);
  }

  /// Buttons of the notification, lock screen and headset.
  void _onCommand(String name) {
    if (name == 'play') {
      resume();
    } else if (name == 'pause') {
      pause();
    } else if (name == 'next') {
      next();
    } else if (name == 'prev') {
      prev();
    } else if (name == 'toggle') {
      togglePlay();
    } else if (name == 'skipback') {
      skip(-prefs.skipSec);
    } else if (name == 'skipfwd') {
      skip(prefs.skipSec);
    } else if (name == 'plugged') {
      if (prefs.plugPlay && current != null && !playing) resume();
    } else if (name.startsWith('seek:')) {
      final ms = int.tryParse(name.substring(5));
      if (ms != null) seekTo(ms);
    }
  }

  // ---------------------------------------------------------------- backup
  String backupText() => jsonEncode({'app': 'Athana', 'format': 2, 'version': kVersion, 'prefs': prefs.toJson()});

  bool restoreBackup(String text) {
    try {
      final j = Map<String, dynamic>.from(jsonDecode(text) as Map);
      if (j['app'] != 'Athana' || j['prefs'] is! Map) return false;
      prefs.load(Map<String, dynamic>.from(j['prefs'] as Map));
      savePrefs();
      eqApply();
      mixApply();
      normApply();
      return true;
    } catch (_) {
      return false;
    }
  }

  void resetOptions() {
    prefs.load(Prefs().toJson());
    savePrefs();
    eqApply();
    _mixLatched = false;
    mixApply();
    normApply();
  }
}

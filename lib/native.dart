import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'models.dart';

/// The bridge to the Android side (Kotlin). Playback is done by Media3 ExoPlayer there, so Flutter never decodes audio itself.
class Native {
  static const MethodChannel _m = MethodChannel('athana/native');
  static const EventChannel _e = EventChannel('athana/events');

  static Stream<Map<String, dynamic>> get events =>
      _e.receiveBroadcastStream().map((dynamic e) => Map<String, dynamic>.from(e as Map));

  static List<Map<String, dynamic>> _songs(dynamic raw) {
    if (raw == null) return <Map<String, dynamic>>[];
    return (raw as List).map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Opens Android's folder picker. Returns {tree, name, songs} or null if cancelled.
  static Future<Map<String, dynamic>?> pickFolder({bool drive = false}) async {
    final dynamic r = await _m.invokeMethod<dynamic>('pickFolder', {'drive': drive});
    if (r == null) return null;
    final m = Map<String, dynamic>.from(r as Map);
    m['songs'] = _songs(m['songs']);
    return m;
  }

  /// Opens Android's file picker (several songs). Returns the songs or null if cancelled.
  static Future<List<Map<String, dynamic>>?> pickFiles({bool drive = false}) async {
    final dynamic r = await _m.invokeMethod<dynamic>('pickFiles', {'drive': drive});
    if (r == null) return null;
    return _songs(r);
  }

  /// Lists the songs of a folder that was linked before. Null when Android no longer allows access.
  static Future<List<Map<String, dynamic>>?> scanTree(String tree) async {
    final dynamic r = await _m.invokeMethod<dynamic>('scanTree', {'tree': tree});
    if (r == null) return null;
    return _songs(r);
  }

  static Future<void> releaseTree(String tree) => _m.invokeMethod<void>('releaseTree', {'tree': tree});

  /// Title, artist, album, length and a small cover file for one song.
  static Future<Map<String, dynamic>> meta(Track t) async {
    final dynamic r = await _m.invokeMethod<dynamic>('meta', {'uri': t.uri, 'name': t.name, 'folderArt': t.folderArt});
    return r == null ? <String, dynamic>{} : Map<String, dynamic>.from(r as Map);
  }

  static Future<void> play(int token, Track t) => _m.invokeMethod<void>('play', {
        'token': token,
        'uri': t.uri,
        'name': t.name,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'art': t.art ?? '',
        'aiff': t.isAiff,
      });

  /// Updates the title, artist and cover shown in the notification, without restarting the song.
  static Future<void> updateInfo(Track t) => _m.invokeMethod<void>('updateMeta', {
        'uri': t.uri,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'art': t.art ?? '',
      });

  // Offline copies of cloud songs (Google Drive and similar). Each song is saved once, in the background.
  static Future<bool> offlineStart(List<Map<String, String>> items, bool wifiOnly, {bool force = false, int limit = 0}) async =>
      (await _m.invokeMethod<bool>('offlineStart', {'items': items, 'wifi': wifiOnly, 'force': force, 'limit': limit})) ?? false;
  static Future<void> offlineClearQueue() => _m.invokeMethod<void>('offlineClearQueue');
  static Future<void> offlineTrim(int limit) => _m.invokeMethod<void>('offlineTrim', {'limit': limit});
  static Future<void> offlineStop() => _m.invokeMethod<void>('offlineStop');
  static Future<void> offlineClear() => _m.invokeMethod<void>('offlineClear');
  static Future<Map<String, dynamic>> offlineStatus() async =>
      Map<String, dynamic>.from(await _m.invokeMethod<dynamic>('offlineStatus') as Map);

  static Future<void> resume() => _m.invokeMethod<void>('resume');
  static Future<void> pause() => _m.invokeMethod<void>('pause');
  static Future<void> stop() => _m.invokeMethod<void>('stop');
  static Future<void> seek(int ms) => _m.invokeMethod<void>('seek', {'ms': ms});
  static Future<void> setSpeed(double rate) => _m.invokeMethod<void>('setSpeed', {'rate': rate});
  /// Sends the equalizer: on/off, preamp (dB) and the ten band gains (dB).
  static Future<void> eqSet(bool on, double pre, List<double> gains) => _m.invokeMethod<void>('eqSet', {'on': on, 'pre': pre, 'gains': gains});
  /// Loudness normalisation: on/off and the target in LUFS.
  static Future<void> normSet(bool on, double target) => _m.invokeMethod<void>('normSet', {'on': on, 'target': target});
  /// Lyrics saved inside the song file (plain text, or LRC text when they are synced). Null when there are none.
  static Future<String?> lyrics(String uri) => _m.invokeMethod<String>('lyrics', {'uri': uri});
  /// Lets you pick a picture; returns the path of the shrunken copy kept inside the app, or null.
  /// Saves downloaded cover bytes as a small JPEG in Athana's storage and returns its path (empty when it could not be read).
  static Future<String?> saveCoverBytes(Uint8List bytes) => _m.invokeMethod<String>('saveCoverBytes', {'bytes': bytes});

  static Future<String?> pickImage({bool cover = false}) => _m.invokeMethod<String>('pickImage', {'cover': cover});
  /// Lets you pick a lyrics file (.lrc or .txt); returns its text, or null.
  /// A Drive song got a new link: moves its saved copy (if any) over to the new link, so it is not downloaded again.
  /// Gets the next Drive songs ready in a temporary folder (they are not saved). [current] is the song playing now; an empty list clears the copies.
  static Future<void> warm(String current, List<Map<String, String>> items, bool wifiOnly) =>
      _m.invokeMethod<void>('warm', {'current': current, 'items': items, 'wifi': wifiOnly});
  /// How far the playing song has loaded: {'settled': loaded about 30 s ahead / fully / read from a copy on the phone, 'local': a copy is used, 'ahead': ms}.
  static Future<Map<String, dynamic>> bufInfo() async =>
      Map<String, dynamic>.from(await _m.invokeMethod<Map<Object?, Object?>>('bufInfo') ?? const <Object?, Object?>{});
  static Future<void> offlineRekey(String oldUri, String newUri) => _m.invokeMethod<void>('offlineRekey', {'old': oldUri, 'new': newUri});

  /// Lets the user pick a text file and returns its text. [big] allows a large file (a lyrics backup) instead of a single .lrc.
  static Future<String?> pickText({bool big = false}) => _m.invokeMethod<String>('pickText', {'big': big});

  /// Lets the user choose where to save [text] as a file. Returns true when it was written.
  static Future<bool> saveText(String name, String text) async => (await _m.invokeMethod<bool>('saveText', {'name': name, 'text': text})) ?? false;
  /// Opens a web address (used to download an update).
  static Future<bool> openUrl(String url) async => (await _m.invokeMethod<bool>('openUrl', {'url': url})) ?? false;
  static Future<void> moveToBack() => _m.invokeMethod<void>('moveToBack');
  static Future<void> headset(String a1, String a2, String a3, bool unplugPause) =>
      _m.invokeMethod<void>('headset', {'a1': a1, 'a2': a2, 'a3': a3, 'unplugPause': unplugPause});
  static Future<void> mixSet(bool active, double bal, double wide, bool mono, double vol, double cross) =>
      _m.invokeMethod<void>('mixSet', {'active': active, 'bal': bal, 'wide': wide, 'mono': mono, 'vol': vol, 'cross': cross});
  /// Where the sound goes now: {kind: speaker | wired | usb | bluetooth, name}.
  static Future<Map<String, String>> output() async {
    final dynamic r = await _m.invokeMethod<dynamic>('output');
    return r is Map ? r.map((dynamic k, dynamic v) => MapEntry(k.toString(), v.toString())) : <String, String>{};
  }
  /// A folder for a downloaded update (emptied first).
  static Future<String> updateDir() async => (await _m.invokeMethod<String>('updateDir')) ?? '';
  /// Opens Android's installer for a downloaded APK. Returns ok, permission (Android asked for the install permission) or missing.
  static Future<String> installApk(String path) async => (await _m.invokeMethod<String>('installApk', {'path': path})) ?? 'missing';
  /// The folders Android still lets Athana read.
  static Future<Set<String>> treeAccess() async {
    final dynamic r = await _m.invokeMethod<dynamic>('treeAccess');
    return r is List ? r.map((dynamic e) => e.toString()).toSet() : <String>{};
  }
  /// Reads the whole song and measures it. Returns null when it was cancelled or cannot be read.
  static Future<Map<String, dynamic>?> analyze(Track t) async {
    final dynamic r = await _m.invokeMethod<dynamic>('analyze', {'uri': t.uri, 'aiff': t.isAiff, 'bits': t.bits, 'durationMs': t.durationMs});
    return r == null ? null : Map<String, dynamic>.from(r as Map);
  }
  static Future<void> analyzeCancel() => _m.invokeMethod<void>('analyzeCancel');
  /// A–B loop points in milliseconds (-1 = not set).
  static Future<void> loopSet(int a, int b) => _m.invokeMethod<void>('loopSet', {'a': a, 'b': b});
  /// Fade each song out at its end and the next one in, over this many seconds (0 = off).
  /// Fades the music out over [sec] seconds and pauses it (the sleep timer).
  static Future<void> sleepFade(int sec) => _m.invokeMethod<void>('sleepFade', {'sec': sec});
  static Future<void> sleepFadeCancel() => _m.invokeMethod<void>('sleepFadeCancel');
  static Future<void> fadeSet(int sec) => _m.invokeMethod<void>('fadeSet', {'sec': sec});
  static Future<void> keepAwake(bool on) => _m.invokeMethod<void>('keepAwake', {'on': on});
  /// dir: 1 louder, -1 quieter, 0 mute / unmute. Uses the phone's own media volume.
  static Future<void> volume(int dir) => _m.invokeMethod<void>('volume', {'dir': dir});

  /// The phone's media volume: the current step and the highest step.
  static Future<(int, int)> volumeInfo() async {
    final m = Map<String, dynamic>.from(await _m.invokeMethod<dynamic>('volumeGet') as Map);
    return (((m['cur'] ?? 0) as num).toInt(), ((m['max'] ?? 15) as num).toInt());
  }

  /// Athana's own audio code: {flac, out, bp: the switches; active, outActive: is it in use for the current song}.
  static Future<Map<String, dynamic>> engineInfo() async {
    final r = await _m.invokeMethod<dynamic>('engineGet');
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  /// Sets Athana's own audio switches: [flac] is the decoder, [out] the audio output, [bp] Android's bit-perfect mixer.
  static Future<void> engineSet({bool? flac, bool? out, bool? bp}) =>
      _m.invokeMethod<void>('engineSet', {if (flac != null) 'flac': flac, if (out != null) 'out': out, if (bp != null) 'bp': bp});

  static Future<void> volumeSet(int level) => _m.invokeMethod<void>('volumeSet', {'level': level});
}
